defmodule Googen.Generator.Endpoint do
  @moduledoc """
  A single callable API method: an HTTP verb + path + parameters. Required
  parameters become positional args; optional ones ride in `opts`.

  Methods that support media upload additionally yield `_media` (raw bytes) and
  `_multipart` (metadata + bytes) variants that post to the upload endpoint.
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
    is_download: false,
    upload: nil
  ]

  @type t :: %__MODULE__{}

  @doc "The endpoint(s) for a discovery method named `verb`."
  @spec from_method(String.t(), map, ResourceContext.t()) :: [t]
  def from_method(verb, method, ctx) do
    basic = basic(verb, method, ctx)

    case upload_path(method) do
      nil ->
        [basic]

      path ->
        [basic, media_upload(verb, method, path, ctx), multipart_upload(verb, method, path, ctx)]
    end
  end

  defp upload_path(method), do: get_in(method, [:mediaUpload, :protocols, :simple, :path])

  defp basic(verb, method, ctx) do
    {required, optional} = Parameter.from_method(method, ctx)

    build(
      Macro.underscore(verb),
      method,
      "/" <> ResourceContext.path(ctx, method[:path]),
      required,
      optional,
      ctx,
      nil
    )
  end

  defp media_upload(verb, method, path, ctx) do
    {required, optional} = Parameter.from_method(method, ctx)
    required = required ++ [data_param()]
    optional = Enum.reject(optional, &(&1.location == "body"))
    build(Macro.underscore(verb) <> "_media", method, path, required, optional, ctx, :media)
  end

  defp multipart_upload(verb, method, path, ctx) do
    {required, optional} = Parameter.from_method(method, ctx)
    required = required ++ [metadata_param(method, ctx), data_param()]
    optional = Enum.reject(optional, &(&1.location == "body"))

    build(
      Macro.underscore(verb) <> "_multipart",
      method,
      path,
      required,
      optional,
      ctx,
      :multipart
    )
  end

  defp build(name, method, path, required, optional, ctx, upload) do
    ret = return_type(method, ctx)

    %__MODULE__{
      name: name,
      description: method[:description],
      method: method[:httpMethod] |> String.downcase() |> String.to_atom(),
      path: path,
      required_parameters: required,
      optional_parameters: optional,
      path_parameters: Enum.filter(required, &(&1.location == "path")),
      is_download: method[:supportsMediaDownload] || false,
      upload: upload,
      return: ret,
      typespec: typespec(name, required, ret)
    }
  end

  defp data_param do
    %Parameter{
      name: "data",
      wire: "data",
      variable_name: "data",
      description:
        "Content to upload: iodata, or a `File.Stream` (e.g. `File.stream!(path)`) to stream from disk.",
      type: %Type{name: "iodata", typespec: "iodata() | File.Stream.t()", decode: :raw},
      location: "media"
    }
  end

  defp metadata_param(method, ctx) do
    %Parameter{
      name: "metadata",
      wire: "metadata",
      variable_name: "metadata",
      description: "Resource metadata to store alongside the content.",
      type: Type.from_schema(method[:request] || %{type: "object"}, ctx),
      location: "body"
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
