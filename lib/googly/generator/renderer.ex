defmodule Googly.Generator.Renderer do
  @moduledoc """
  Renders generated source from EEx templates. Helper functions here are called
  directly from the templates.
  """

  require EEx

  @tpl Path.expand("../../../templates/client", __DIR__)

  # Fallback documentation host when a discovery doc omits `documentationLink`,
  # and the base for absolutizing root-relative links in descriptions.
  @default_docs_link "https://cloud.google.com/"

  EEx.function_from_file(:def, :model, Path.join(@tpl, "model.ex.eex"), [
    :model,
    :root,
    :docs_link
  ])

  EEx.function_from_file(:def, :api, Path.join(@tpl, "api.ex.eex"), [
    :api,
    :root,
    :global_params,
    :docs_link
  ])

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
    :example_fun,
    :example_args
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
    {resource, fun, args} = example_call(token)

    readme_tpl(
      token.module_root,
      token.package_name,
      version(token),
      description(token),
      title(token),
      docs_link(token),
      resource,
      fun,
      args
    )
  end

  def formatter,
    do: "[\n  inputs: [\"{mix,.formatter}.exs\", \"{config,lib,test}/**/*.{ex,exs}\"]\n]\n"

  def gitignore, do: "/_build/\n/cover/\n/deps/\n/doc/\n/mix.lock\nerl_crash.dump\n*.ez\n*.beam\n"

  # -- template helpers -------------------------------------------------------

  @doc """
  Formats a description for embedding in a heredoc `@doc`, indenting wrapped
  lines and repairing the Markdown quirks in Google's prose (see
  `normalize_markdown_links/2` and `close_dangling_inline_code/1`). `base_url`
  is the API's documentation host, used to absolutize root-relative links.
  """
  def doc(str, indent, base_url \\ @default_docs_link)
  def doc(nil, _indent, _base_url), do: ""

  def doc(str, indent, base_url) do
    prefix = String.duplicate(" ", indent)

    str
    |> normalize_markdown_links(base_url)
    |> close_dangling_inline_code()
    |> String.replace("\\", "\\\\")
    |> String.replace(~s("""), ~s(\\"\\"\\"))
    |> String.replace("\#{", "\\\#{")
    |> String.replace(~r/(\n+)([^\n])/, "\\1#{prefix}\\2")
  end

  # Google descriptions carry root-relative doc links (`](/foo/bar)`); ExDoc reads
  # those as local file references and warns. Resolve each against the API's own
  # documentation host (`base_url`) so it becomes a real URL — Cloud Storage lives
  # under developers.google.com, most others under cloud.google.com. Absolute and
  # protocol-relative (`//host`) targets are left alone.
  defp normalize_markdown_links(str, base_url) do
    Regex.replace(~r{\]\((/(?!/)[^)\s]*)\)}, str, fn _match, path ->
      "](" <> URI.to_string(URI.merge(base_url, path)) <> ")"
    end)
  end

  # Some descriptions open an inline `code` span they never close, which makes
  # EarmarkParser (ExDoc) warn about "unclosed backquotes". This is upstream-prose
  # repair, not real Markdown parsing (not worth a parser dependency): when the
  # backtick count is odd, append one to close the dangling span.
  defp close_dangling_inline_code(str) do
    odd? = str |> String.graphemes() |> Enum.count(&(&1 == "`")) |> rem(2) == 1
    if odd?, do: str <> "`", else: str
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

  defp path_value(%{type: %{name: "string"}, reserved?: true, variable_name: v}),
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

  @doc """
  The client's version: preserved from the existing `mix.exs` across
  regenerations (release bumps it), or `0.1.0` for a brand-new client.
  """
  def version(token) do
    path = Path.join(token.root_dir, "mix.exs")

    with {:ok, content} <- File.read(path),
         [_, current] <- Regex.run(~r/@version "([\d.]+)"/, content) do
      current
    else
      _ -> "0.1.0"
    end
  end

  # Google's discovery titles omit "Google" ("Cloud Storage JSON API"), which
  # hurts Hex search — prefix it (unless already present). Feeds the package
  # description and the README.
  defp title(token) do
    raw = token.rest[:title] || token.module_root
    if String.contains?(raw, "Google"), do: raw, else: "Google " <> raw
  end

  @doc "The API's documentation URL, or the Google-docs fallback."
  def docs_link(token), do: token.rest[:documentationLink] || @default_docs_link

  defp description(token) do
    base = "#{title(token)} client library."
    extra = token.rest[:description]

    cond do
      is_nil(extra) -> base
      String.length(base) + String.length(extra) > 200 -> base
      true -> "#{base} #{extra}"
    end
  end

  # The README's example call. Any endpoint would compile, but the example is
  # the reader's first impression, so pick a safe read-only one: an HTTP GET
  # (a POST would silently send no `:body`; a DELETE example is destructive),
  # preferring plain `get`/`list` names, fewer required arguments, and
  # shallower resources — deterministically, so regeneration is stable.
  defp example_call(token) do
    candidates = for api <- token.apis, endpoint <- api.endpoints, do: {api, endpoint}

    case Enum.filter(candidates, fn {_api, endpoint} -> endpoint.method == :get end) do
      [] -> example_call_from(List.first(candidates))
      gets -> example_call_from(Enum.min_by(gets, &example_rank/1))
    end
  end

  defp example_call_from({api, endpoint}),
    do: {api.name, endpoint.name, example_args(endpoint)}

  defp example_call_from(nil), do: {"Resource", "call", ""}

  defp example_rank({api, endpoint}) do
    name_rank =
      case endpoint.name do
        "get" -> 0
        "list" -> 1
        _ -> 2
      end

    depth = api.name |> String.split(".") |> length()
    {name_rank, length(endpoint.required_parameters), depth, api.name, endpoint.name}
  end

  # Placeholder positional arguments (with trailing comma) for the README example
  # call, mirroring `signature_args/1` but with literal placeholders standing in
  # for the required params. Empty when the endpoint takes none.
  defp example_args(%{required_parameters: []}), do: ""

  defp example_args(%{required_parameters: ps}),
    do: Enum.map_join(ps, ", ", &example_value/1) <> ", "

  defp example_value(%{type: %{name: name}, variable_name: v}) do
    case name do
      n when n in ["integer", "number", "float"] -> "0"
      "boolean" -> "false"
      _ -> inspect(v)
    end
  end
end
