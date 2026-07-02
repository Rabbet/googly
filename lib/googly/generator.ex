defmodule Googly.Generator do
  @moduledoc """
  Turns a cached discovery document into a self-contained Elixir client package
  under `clients/<package>/`.
  """

  require Logger

  alias Googly.Generator.Api
  alias Googly.Generator.Endpoint
  alias Googly.Generator.Model
  alias Googly.Generator.Parameter
  alias Googly.Generator.Renderer
  alias Googly.Generator.ResourceContext
  alias Googly.Generator.Token

  @doc "Generates the client for `config`. Returns `:ok` or `{:error, reason}`."
  def generate(config) do
    case Token.build(config) do
      nil ->
        {:error,
         "no spec file at #{Googly.ApiConfig.spec_file(config)} — run mix googly.fetch first"}

      token ->
        token
        |> load_models()
        |> put_model_properties()
        |> load_apis()
        |> load_global_params()
        |> create_dirs()
        |> write_models()
        |> write_apis()
        |> write_runtime()
        |> write_package_files()

        :ok
    end
  end

  # -- collection -------------------------------------------------------------

  defp load_models(token) do
    models =
      token.rest[:schemas]
      |> Model.from_schemas()
      |> Enum.sort_by(& &1.name)
      |> dedup_filenames(&Model.filename/1, &%{&1 | filename: &2})

    %{token | models: models, models_by_name: Map.new(models, &{&1.name, &1})}
  end

  defp put_model_properties(token) do
    context = ResourceContext.with_models_by_name(token.context, token.models_by_name)
    %{token | models: Enum.map(token.models, &Model.put_properties(&1, context))}
  end

  defp load_apis(token) do
    apis =
      collect_resources(token.rest[:resources] || %{}, [], token.context)
      |> dedup_filenames(&Api.filename/1, &%{&1 | filename: &2})

    %{token | apis: apis}
  end

  defp collect_resources(resources, prefix, context) do
    Enum.flat_map(resources, fn {name, resource} ->
      segment = name |> to_string() |> String.replace("-", "_") |> Macro.camelize()
      qualified = prefix ++ [segment]

      endpoints =
        (resource[:methods] || %{})
        |> Enum.flat_map(fn {verb, method} ->
          Endpoint.from_method(to_string(verb), method, context)
        end)
        |> Enum.sort_by(& &1.name)

      subs = collect_resources(resource[:resources] || %{}, qualified, context)

      api = %Api{
        name: Enum.join(qualified, "."),
        description: "Endpoints for the `#{Enum.join(qualified, ".")}` resource.",
        endpoints: endpoints
      }

      if endpoints == [], do: subs, else: [api | subs]
    end)
  end

  defp load_global_params(token) do
    params =
      (token.rest[:parameters] || %{})
      |> Enum.map(fn {name, schema} ->
        Parameter.from_method_param(to_string(name), schema, token.context)
      end)
      |> Enum.sort_by(& &1.name)

    %{token | global_params: params}
  end

  # -- writing ----------------------------------------------------------------

  defp create_dirs(token) do
    File.rm_rf!(token.lib_dir)
    File.mkdir_p!(Path.join(token.lib_dir, "model"))
    token
  end

  defp write_models(token) do
    Enum.each(token.models, fn model ->
      path = Path.join([token.lib_dir, "model", model.filename])
      File.write!(path, Renderer.model(model, token.module_root))
    end)

    Logger.info("Wrote #{length(token.models)} models")
    token
  end

  defp write_apis(token) do
    Enum.each(token.apis, fn api ->
      path = Path.join(token.lib_dir, api.filename)
      File.mkdir_p!(Path.dirname(path))
      File.write!(path, Renderer.api(api, token.module_root, token.global_params))
    end)

    Logger.info("Wrote #{length(token.apis)} resource modules")
    token
  end

  defp write_runtime(token) do
    model_modules =
      Enum.map(token.models, &"#{token.module_root}.Model.#{Macro.camelize(&1.name)}")

    File.write!(
      Path.join(token.lib_dir, "request.ex"),
      Renderer.request(token.module_root, token.base_url)
    )

    File.write!(Path.join(token.lib_dir, "response.ex"), Renderer.response(token.module_root))
    File.write!(Path.join(token.lib_dir, "decode.ex"), Renderer.decode(token.module_root))
    File.write!(Path.join(token.lib_dir, "error.ex"), Renderer.error(token.module_root))

    File.write!(
      Path.join(token.lib_dir, "encoder.ex"),
      Renderer.encoder(token.module_root, model_modules)
    )

    token
  end

  defp write_package_files(token) do
    File.write!(Path.join(token.root_dir, "mix.exs"), Renderer.mix_exs(token))
    File.write!(Path.join(token.root_dir, "README.md"), Renderer.readme(token))
    File.write!(Path.join(token.root_dir, "LICENSE"), Renderer.license())
    File.write!(Path.join(token.root_dir, ".formatter.exs"), Renderer.formatter())
    File.write!(Path.join(token.root_dir, ".gitignore"), Renderer.gitignore())
    token
  end

  # -- helpers ----------------------------------------------------------------

  # Ensures generated file names are unique, suffixing `_1`, `_2`, ... on clashes.
  defp dedup_filenames(items, name_fun, put_fun) do
    {items, _} =
      Enum.map_reduce(items, MapSet.new(), fn item, used ->
        {file, used} = unique(name_fun.(item), used, 0)
        {put_fun.(item, file), used}
      end)

    items
  end

  defp unique(name, used, n) do
    candidate = if n == 0, do: name, else: "#{Path.rootname(name)}_#{n}.ex"

    if MapSet.member?(used, candidate),
      do: unique(name, used, n + 1),
      else: {candidate, MapSet.put(used, candidate)}
  end
end
