defmodule Googen.Generator.Property do
  @moduledoc """
  A field of a model. `name` is the snake_case Elixir struct key; `wire` is the
  exact JSON key from the discovery document (they differ for e.g. `timeCreated`
  / `time_created`, and `satisfiesPZS` / `satisfies_pzs`).
  """

  alias Googen.Generator.ResourceContext
  alias Googen.Generator.Type

  @enforce_keys [:name, :wire, :type]
  defstruct [:name, :wire, :type, :description, :default]

  @type t :: %__MODULE__{
          name: String.t(),
          wire: String.t(),
          type: Type.t(),
          description: String.t() | nil,
          default: term()
        }

  @spec from_schema(map, String.t(), ResourceContext.t()) :: t
  def from_schema(schema, wire, context) do
    %__MODULE__{
      name: Macro.underscore(wire),
      wire: wire,
      type: Type.from_schema(schema, ResourceContext.with_property(context, wire)),
      description: schema[:description],
      default: schema[:default]
    }
  end
end
