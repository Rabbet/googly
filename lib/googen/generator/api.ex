defmodule Googen.Generator.Api do
  @moduledoc "A resource: a named group of endpoints (e.g. `Objects`, `Buckets`)."

  alias Googen.Generator.Endpoint

  @enforce_keys [:name]
  defstruct [:name, :filename, :description, endpoints: []]

  @type t :: %__MODULE__{
          name: String.t(),
          filename: String.t() | nil,
          description: String.t() | nil,
          endpoints: [Endpoint.t()]
        }

  def filename(%__MODULE__{name: name}), do: "#{Macro.underscore(name)}.ex"
end
