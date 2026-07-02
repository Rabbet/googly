defmodule Googly.Generator.Renderer do
  @moduledoc """
  Renders generated source from EEx templates. Helper functions here are called
  directly from the templates.
  """

  require EEx

  @tpl Path.expand("../../../templates/client", __DIR__)

  EEx.function_from_file(:def, :model, Path.join(@tpl, "model.ex.eex"), [:model, :root])
  EEx.function_from_file(:def, :api, Path.join(@tpl, "api.ex.eex"), [:api, :root, :global_params])
  EEx.function_from_file(:def, :request, Path.join(@tpl, "request.ex.eex"), [:root, :base_url])
  EEx.function_from_file(:def, :response, Path.join(@tpl, "response.ex.eex"), [:root])
  EEx.function_from_file(:def, :decode, Path.join(@tpl, "decode.ex.eex"), [:root])
  EEx.function_from_file(:def, :error, Path.join(@tpl, "error.ex.eex"), [:root])
  EEx.function_from_file(:def, :encoder, Path.join(@tpl, "encoder.ex.eex"), [:root, :modules])
  EEx.function_from_file(:def, :license, Path.join(@tpl, "LICENSE.eex"), [])

  EEx.function_from_file(:def, :mix_exs_tpl, Path.join(@tpl, "mix.exs.eex"), [
    :root,
    :package,
    :version,
    :description,
    :docs_link
  ])

  EEx.function_from_file(:def, :readme_tpl, Path.join(@tpl, "README.md.eex"), [
    :root,
    :package,
    :version,
    :description,
    :title,
    :docs_link,
    :example_resource,
    :example_fun
  ])

  # -- package-file wrappers (compute derived values from the token) ----------

  def mix_exs(token) do
    mix_exs_tpl(
      token.module_root,
      token.package_name,
      version(token),
      description(token),
      docs_link(token)
    )
  end

  def readme(token) do
    {resource, fun} = example_call(token)

    readme_tpl(
      token.module_root,
      token.package_name,
      version(token),
      description(token),
      title(token),
      docs_link(token),
      resource,
      fun
    )
  end

  def formatter,
    do: "[\n  inputs: [\"{mix,.formatter}.exs\", \"{config,lib,test}/**/*.{ex,exs}\"]\n]\n"

  def gitignore, do: "/_build/\n/cover/\n/deps/\n/doc/\n/mix.lock\nerl_crash.dump\n*.ez\n*.beam\n"

  # -- template helpers -------------------------------------------------------

  @doc "Formats a description for embedding in a heredoc `@doc`, indenting wrapped lines."
  def doc(nil, _indent), do: ""

  def doc(str, indent) do
    prefix = String.duplicate(" ", indent)

    str
    |> String.replace("\\", "\\\\")
    |> String.replace(~s("""), ~s(\\"\\"\\"))
    |> String.replace("\#{", "\\\#{")
    |> String.replace(~r/(\n+)([^\n])/, "\\1#{prefix}\\2")
  end

  @doc "True when a model needs the `Decode` helper aliased."
  def uses_decode?(model) do
    Enum.any?(model.properties, fn p ->
      match?(:datetime, p.type.decode) or match?(:date, p.type.decode) or
        match?({:list, _}, p.type.decode) or match?({:map, _}, p.type.decode)
    end)
  end

  @doc "The `__wire__/0` map literal for a model (only fields whose name differs from the wire)."
  def wire_map(model) do
    entries = for p <- model.properties, p.name != p.wire, do: "#{p.name}: #{inspect(p.wire)}"
    "%{" <> Enum.join(entries, ", ") <> "}"
  end

  @doc "The right-hand side that decodes property `p` from the JSON map `m`."
  def decode_rhs(%{wire: wire, type: %{decode: decode}}) do
    v = "m[#{inspect(wire)}]"

    case decode do
      :raw -> v
      :datetime -> "Decode.datetime(#{v})"
      :date -> "Decode.date(#{v})"
      {:struct, mod} -> "#{mod}.decode(#{v})"
      {:list, :datetime} -> "Decode.list(#{v}, DateTime)"
      {:list, :date} -> "Decode.list(#{v}, Date)"
      {:map, mod} -> "Decode.map(#{v}, #{mod})"
    end
  end

  @doc "Optional parameters (global + endpoint-specific) shown in docs and specs."
  def optional_params(ep, global), do: global ++ ep.optional_parameters

  @doc "Positional-argument prefix for an endpoint's function head (with trailing comma)."
  def signature_args(%{required_parameters: []}), do: ""

  def signature_args(%{required_parameters: ps}),
    do: Enum.map_join(ps, ", ", & &1.variable_name) <> ", "

  @doc "Path-template substitutions map body: `\"wire\" => value`."
  def path_params(ep) do
    Enum.map_join(ep.path_parameters, ", ", fn p -> "#{inspect(p.wire)} => #{path_value(p)}" end)
  end

  defp path_value(%{type: %{name: "string"}, is_path_trailer: true, variable_name: v}),
    do: "URI.encode(#{v}, &(URI.char_unreserved?(&1) or &1 == ?/))"

  defp path_value(%{type: %{name: "string"}, variable_name: v}),
    do: "URI.encode(#{v}, &URI.char_unreserved?/1)"

  defp path_value(%{variable_name: v}), do: v

  @doc "Required query parameters as `{\"wire\", var}` entries."
  def required_query(ep) do
    ep.required_parameters
    |> Enum.filter(&(&1.location == "query"))
    |> Enum.map_join(", ", fn p -> "{#{inspect(p.wire)}, #{p.variable_name}}" end)
  end

  @doc "The optional-parameter routing map: `name: {:query, \"wire\"}` / `name: {:body, nil}`."
  def param_specs(ep, global) do
    (global ++ ep.optional_parameters)
    |> Enum.uniq_by(& &1.name)
    |> Enum.map_join(", ", fn
      %{location: "body", name: name} -> "#{name}: {:body, nil}"
      %{name: name, wire: wire} -> "#{name}: {:query, #{inspect(wire)}}"
    end)
  end

  @doc "The `uploadType` query value for an upload endpoint."
  def upload_type(%{upload: :media}), do: "media"
  def upload_type(%{upload: :multipart}), do: "multipart"

  @doc "The module a successful response decodes into, or `nil` for raw responses."
  def decode_target(ep, _root) do
    case ep.return.struct do
      s when s in [nil, "Date", "DateTime"] -> "nil"
      mod -> mod
    end
  end

  @doc "Return-value shown in an endpoint's `@doc`."
  def return_doc(%{struct: s}) when s not in [nil, "Date", "DateTime"], do: "%#{s}{}"
  def return_doc(_), do: "Req.Response.t()"

  # -- derived package metadata ----------------------------------------------

  # Preserve the existing version across regenerations (release bumps it); new
  # clients start at 0.1.0.
  defp version(token) do
    path = Path.join(token.root_dir, "mix.exs")

    with {:ok, content} <- File.read(path),
         [_, current] <- Regex.run(~r/@version "([\d.]+)"/, content) do
      current
    else
      _ -> "0.1.0"
    end
  end

  defp title(token), do: token.rest[:title] || token.module_root

  defp docs_link(token), do: token.rest[:documentationLink] || "https://cloud.google.com/"

  defp description(token) do
    base = "#{title(token)} client library."
    extra = token.rest[:description]

    cond do
      is_nil(extra) -> base
      String.length(base) + String.length(extra) > 200 -> base
      true -> "#{base} #{extra}"
    end
  end

  defp example_call(token) do
    with %{name: resource, endpoints: [%{name: fun} | _]} <- List.first(token.apis) do
      {resource, fun}
    else
      _ -> {"Resource", "call"}
    end
  end
end
