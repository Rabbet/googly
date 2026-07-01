defmodule Googen.Generator.Model do
  @moduledoc """
  A resource type used by the API. Inline (anonymous) object schemas become
  their own models, named by their nesting path — e.g. the `objectRetention`
  field of `Bucket` yields a `BucketObjectRetention` model.
  """

  alias Googen.Generator.Property
  alias Googen.Generator.ResourceContext

  @enforce_keys [:name]
  defstruct [:name, :filename, :description, :schema, properties: [], is_array: false]

  @type t :: %__MODULE__{
          name: String.t(),
          filename: String.t() | nil,
          description: String.t() | nil,
          schema: map() | nil,
          properties: [Property.t()],
          is_array: boolean()
        }

  @doc "Default file name for a model, e.g. `bucket_object_retention.ex`."
  def filename(%__MODULE__{name: name}), do: "#{Macro.underscore(name)}.ex"

  @doc "Every model (including nested inline objects) declared in a schema map."
  @spec from_schemas(map) :: [t]
  def from_schemas(nil), do: []

  def from_schemas(schemas) do
    Enum.flat_map(schemas, fn {name, schema} ->
      from_schema(to_string(name), schema, ResourceContext.empty())
    end)
  end

  defp from_schema(name, %{type: "object", properties: properties} = schema, context)
       when not is_nil(properties) do
    nested =
      Enum.flat_map(properties, fn {n, s} ->
        from_schema(to_string(n), s, ResourceContext.with_property(context, name))
      end)

    model = %__MODULE__{
      name: ResourceContext.name(context, name),
      description: schema[:description],
      schema: schema
    }

    [model | nested]
  end

  # A self-referential named object with no properties still gets an (empty) struct.
  defp from_schema(name, %{type: "object", id: name} = schema, context) do
    [
      %__MODULE__{
        name: ResourceContext.name(context, name),
        description: schema[:description],
        schema: %{properties: %{}}
      }
    ]
  end

  defp from_schema(name, %{type: "array", items: items}, context) do
    case from_schema(name, items, context) do
      [model | nested] -> [%{model | is_array: true} | nested]
      [] -> []
    end
  end

  defp from_schema(_, _, _), do: []

  @doc "Resolves each model's property types against the full model set."
  @spec put_properties(t, ResourceContext.t()) :: t
  def put_properties(model, context) do
    props =
      (model.schema[:properties] || %{})
      |> Enum.map(fn {name, schema} ->
        Property.from_schema(
          schema,
          to_string(name),
          ResourceContext.with_property(context, model.name)
        )
      end)
      |> Enum.sort_by(& &1.name)

    %{model | properties: props, schema: nil}
  end
end
