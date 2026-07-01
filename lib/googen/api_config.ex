defmodule Googen.ApiConfig do
  @moduledoc """
  A single entry from `config/apis.json` describing a Google API to generate.

  `name` is the verbatim module segment (e.g. `"Storage"`, `"DocumentAI"`); the
  package name and module namespace are derived from it.
  """

  @enforce_keys [:name, :version, :url]
  defstruct [:name, :version, :url]

  @type t :: %__MODULE__{name: String.t(), version: String.t(), url: String.t()}

  @doc "Hex package name, e.g. `\"gcp_storage\"`."
  def package_name(%__MODULE__{name: name}), do: "gcp_" <> Macro.underscore(name)

  @doc "Root module namespace, e.g. `\"Gcp.Storage\"`."
  def module_root(%__MODULE__{name: name}), do: "Gcp." <> name

  @doc "Directory the generated client is written to, e.g. `\"clients/gcp_storage\"`."
  def client_dir(config) do
    Path.join(Application.get_env(:googen, :clients_dir, "clients"), package_name(config))
  end

  @doc "Cached discovery document path, e.g. `\"specifications/gdd/Storage-v1.json\"`."
  def spec_file(%__MODULE__{name: name, version: version}) do
    dir = Application.get_env(:googen, :specs_dir, "specifications/gdd")
    Path.join(dir, "#{name}-#{version}.json")
  end

  @doc "Loads every configured API."
  @spec load_all() :: [t]
  def load_all do
    "config/apis.json"
    |> File.read!()
    |> Jason.decode!(keys: :atoms)
    |> Enum.map(&struct!(__MODULE__, &1))
  end

  @doc "Loads configured APIs matching `name`."
  @spec load(String.t()) :: [t]
  def load(name), do: Enum.filter(load_all(), &(&1.name == name))
end
