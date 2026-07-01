defmodule Googen.Generator.Endpoint do
  @moduledoc """
  A single callable API method: an HTTP verb + path + parameters. Required
  parameters become positional args; optional ones ride in `opts`.

  Media-upload variants (`_simple`/`_iodata`/`_resumable`) are a planned
  follow-up; for now every method yields its basic JSON endpoint.
  """

  alias Googen.Generator.Parameter
  alias Googen.Generator.ResourceContext
  alias Googen.Generator.Type

  @enforce_keys [:name, :method, :path]
  defstruct [
    :name,
    :description,
    :method,
    :path,
    :typespec,
    :return,
    required_parameters: [],
    optional_parameters: [],
    path_parameters: [],
    is_download: false
  ]

  @type t :: %__MODULE__{}

  @doc "The endpoint(s) for a discovery method named `verb`."
  @spec from_method(String.t(), map, ResourceContext.t()) :: [t]
  def from_method(verb, method, ctx), do: [basic(verb, method, ctx)]

  defp basic(verb, method, ctx) do
    {required, optional} = Parameter.from_method(method, ctx)
    ret = return_type(method, ctx)
    name = Macro.underscore(verb)

    %__MODULE__{
      name: name,
      description: method[:description],
      method: method[:httpMethod] |> String.downcase() |> String.to_atom(),
      path: "/" <> ResourceContext.path(ctx, method[:path]),
      required_parameters: required,
      optional_parameters: optional,
      path_parameters: Enum.filter(required, &(&1.location == "path")),
      is_download: method[:supportsMediaDownload] || false,
      return: ret,
      typespec: typespec(name, required, ret)
    }
  end

  defp return_type(%{response: schema}, ctx) when is_map(schema),
    do: Type.from_schema(schema, ctx)

  defp return_type(_, _), do: Type.empty()

  defp typespec(name, required, ret) do
    args = Enum.map(required, & &1.type.typespec) ++ ["keyword()"]
    ok = if ret.struct in [nil, "Date", "DateTime"], do: "Req.Response.t()", else: ret.typespec
    "#{name}(#{Enum.join(args, ", ")}) :: {:ok, #{ok}} | {:error, term()}"
  end
end
