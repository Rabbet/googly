defmodule Googly.Generator.Parameter do
  @moduledoc """
  An argument to an endpoint. Required parameters become positional function
  arguments (`variable_name`); optional ones are passed via `opts` keyed by
  their snake_case `name`, translated back to `wire` on the query string.
  """

  alias Googly.Generator.ResourceContext
  alias Googly.Generator.Type

  @enforce_keys [:name, :wire, :variable_name, :type, :location]
  defstruct [:name, :wire, :variable_name, :description, :type, :location, is_path_trailer: false]

  @type t :: %__MODULE__{
          name: String.t(),
          wire: String.t(),
          variable_name: String.t(),
          description: String.t() | nil,
          type: Type.t(),
          location: String.t(),
          is_path_trailer: boolean()
        }

  @doc "Splits a method's parameters into `{required, optional}`."
  @spec from_method(map, ResourceContext.t()) :: {[t], [t]}
  def from_method(method, context) do
    params = method[:parameters] || %{}
    order = method[:parameterOrder] || []
    request = method[:request]
    path = method[:path] || ""

    {required, optional} = Enum.split_with(params, fn {_name, schema} -> schema[:required] end)

    required_by_name =
      Map.new(required, fn {name, schema} ->
        {to_string(name), build(to_string(name), schema, context, path)}
      end)

    required = Enum.map(order, &required_by_name[to_string(&1)]) |> Enum.reject(&is_nil/1)

    optional =
      Enum.map(optional, fn {name, schema} -> build(to_string(name), schema, context, path) end)

    optional = if request, do: optional ++ [body_param(request, context)], else: optional

    {required, optional}
  end

  defp body_param(request, context) do
    wire = request[:parameterName] || "body"

    %__MODULE__{
      name: "body",
      wire: wire,
      variable_name: "body",
      description: request[:description],
      type: Type.from_schema(request, context),
      location: "body"
    }
  end

  @doc "Builds a standalone parameter (e.g. a global query parameter)."
  def from_method_param(wire, schema, context), do: build(wire, schema, context, "")

  defp build(wire, schema, context, path) do
    %__MODULE__{
      name: field_name(wire),
      wire: wire,
      variable_name: field_name(wire),
      description: schema[:description],
      type: Type.from_schema(schema, context),
      location: schema[:location] || "query",
      is_path_trailer: path_trailer?(wire, schema, context, path)
    }
  end

  # Snake-cases a wire name into a valid identifier, tolerating `$.xgafv` etc.
  defp field_name(wire) do
    wire
    |> String.replace(~r/[^A-Za-z0-9]+/, "_")
    |> Macro.underscore()
    |> String.replace(~r/_+/, "_")
    |> String.trim("_")
  end

  # The Storage API needs `object`/`destinationObject` path separators encoded
  # even though they trail the path, so they are never treated as trailers.
  defp path_trailer?(wire, _schema, %{namespace: "Googly.CloudStorage"}, _path)
       when wire in ["object", "destinationObject"],
       do: false

  defp path_trailer?(wire, schema, _context, path),
    do: schema[:location] == "path" and String.ends_with?(path, "{#{wire}}")
end
