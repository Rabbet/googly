defmodule Googen.Generator.Type do
  @moduledoc """
  Maps a discovery JSON schema onto an Elixir type: a `typespec` string plus a
  `decode` strategy that drives the generated `decode/1`. Discovery schemas
  arrive as plain maps with atom keys.

  `decode` is one of:

    * `:raw`               — take the JSON value as-is (scalars, plain maps/lists)
    * `:datetime` / `:date`— parse an RFC3339/ISO8601 string
    * `{:struct, mod}`     — `mod.decode/1` (also handles lists and lists-of-lists)
    * `{:list, :datetime}` — a list of temporals
    * `{:list, :date}`
    * `{:map, mod}`        — a `%{String.t() => mod.t()}` map
  """

  alias Googen.Generator.ResourceContext, as: Ctx

  @enforce_keys [:typespec, :decode]
  defstruct [:name, :struct, :typespec, :decode]

  @type t :: %__MODULE__{
          name: String.t() | nil,
          struct: String.t() | nil,
          typespec: String.t(),
          decode: term()
        }

  @spec from_schema(map, Ctx.t()) :: t
  def from_schema(schema, context \\ Ctx.empty())

  # Maps: additionalProperties describes the value type.
  def from_schema(%{additionalProperties: ap}, context) do
    case ap[:"$ref"] do
      nil ->
        %__MODULE__{name: "map", typespec: "map()", decode: :raw}

      ref ->
        %__MODULE__{
          name: "map",
          struct: Ctx.struct_name(context, ref),
          typespec: "%{optional(String.t()) => #{Ctx.typespec(context, ref)}}",
          decode: {:map, Ctx.struct_name(context, ref)}
        }
    end
  end

  # Arrays.
  def from_schema(%{type: "array", items: items}, context) do
    inner = from_schema(items, context)

    %__MODULE__{
      name: "array",
      struct: inner.struct,
      typespec: "list(#{inner.typespec})",
      decode: list_decode(inner)
    }
  end

  # Repeated query params behave like arrays.
  def from_schema(%{repeated: true} = schema, context) do
    inner = from_schema(Map.delete(schema, :repeated), context)

    %__MODULE__{
      name: "array",
      struct: inner.struct,
      typespec: "list(#{inner.typespec})",
      decode: list_decode(inner)
    }
  end

  # References to named schemas.
  def from_schema(%{"$ref": ref}, context) when not is_nil(ref) do
    model = context.models_by_name[ref]
    struct = Ctx.struct_name(context, ref)
    spec = Ctx.typespec(context, ref)

    if model && model.is_array do
      %__MODULE__{
        name: "array",
        struct: struct,
        typespec: "list(#{spec})",
        decode: {:struct, struct}
      }
    else
      %__MODULE__{name: "object", struct: struct, typespec: spec, decode: {:struct, struct}}
    end
  end

  def from_schema(%{type: t}, _context) when t in ["int", "integer"],
    do: %__MODULE__{name: "integer", typespec: "integer()", decode: :raw}

  def from_schema(%{type: "string", format: "date"}, _context),
    do: %__MODULE__{name: "date", struct: "Date", typespec: "Date.t()", decode: :date}

  def from_schema(%{type: "string", format: fmt}, _context)
      when fmt in ["date-time", "time", "google-datetime"],
      do: %__MODULE__{
        name: "datetime",
        struct: "DateTime",
        typespec: "DateTime.t()",
        decode: :datetime
      }

  def from_schema(%{type: "string"}, _context),
    do: %__MODULE__{name: "string", typespec: "String.t()", decode: :raw}

  def from_schema(%{type: "boolean"}, _context),
    do: %__MODULE__{name: "boolean", typespec: "boolean()", decode: :raw}

  def from_schema(%{type: "number", format: "double"}, _context),
    do: %__MODULE__{name: "float", typespec: "float()", decode: :raw}

  def from_schema(%{type: "number"}, _context),
    do: %__MODULE__{name: "number", typespec: "number()", decode: :raw}

  def from_schema(%{type: "any"}, _context),
    do: %__MODULE__{name: "any", typespec: "any()", decode: :raw}

  # An inline object with no additionalProperties becomes its own model.
  def from_schema(%{type: "object"}, context),
    do: %__MODULE__{
      name: "object",
      struct: Ctx.struct_name(context),
      typespec: Ctx.typespec(context),
      decode: {:struct, Ctx.struct_name(context)}
    }

  def from_schema(_schema, _context),
    do: %__MODULE__{name: "string", typespec: "String.t()", decode: :raw}

  @doc "The type of an omitted/empty return value."
  def empty, do: %__MODULE__{name: nil, typespec: "nil", decode: :raw}

  # `mod.decode/1` already recurses over lists and lists-of-lists, so a list of
  # structs needs no special-casing. Only temporal element types do.
  defp list_decode(%{decode: {:struct, _} = d}), do: d
  defp list_decode(%{decode: :datetime}), do: {:list, :datetime}
  defp list_decode(%{decode: :date}), do: {:list, :date}
  defp list_decode(_), do: :raw
end
