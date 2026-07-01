defmodule Googen.Generator.Token do
  @moduledoc """
  Mutable-ish state threaded through the generation pipeline for one API.
  """

  alias Googen.ApiConfig
  alias Googen.Generator.ResourceContext

  defstruct [
    :config,
    :package_name,
    :module_root,
    :root_dir,
    :lib_dir,
    :base_url,
    :rest,
    :context,
    models: [],
    models_by_name: %{},
    apis: [],
    global_params: []
  ]

  @type t :: %__MODULE__{}

  @doc "Builds the initial token by reading and parsing the cached discovery doc."
  @spec build(ApiConfig.t()) :: t | nil
  def build(config) do
    module_root = ApiConfig.module_root(config)
    root_dir = ApiConfig.client_dir(config)
    lib_dir = Path.join([root_dir, "lib" | module_path(module_root)])

    case config |> ApiConfig.spec_file() |> File.read() do
      {:ok, content} ->
        rest = Jason.decode!(content, keys: :atoms)
        service_path = rest[:servicePath] || ""

        context =
          ResourceContext.empty()
          |> ResourceContext.with_namespace(module_root)
          |> ResourceContext.with_base_path(service_path)

        %__MODULE__{
          config: config,
          package_name: ApiConfig.package_name(config),
          module_root: module_root,
          root_dir: root_dir,
          lib_dir: lib_dir,
          base_url: rest[:rootUrl],
          rest: rest,
          context: context
        }

      {:error, _} ->
        nil
    end
  end

  defp module_path(module_root) do
    module_root |> String.split(".") |> Enum.map(&Macro.underscore/1)
  end
end
