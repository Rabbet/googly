defmodule Googen.Generator.ResourceContext do
  @moduledoc """
  Carries naming state while walking a discovery document: the target module
  namespace, the current nested-property prefix (used to name anonymous inline
  schemas), the API base path, and the map of known models by ref name.
  """

  defstruct namespace: "", property: "", base_path: "", models_by_name: %{}

  @type t :: %__MODULE__{
          namespace: String.t(),
          property: String.t(),
          base_path: String.t(),
          models_by_name: map()
        }

  def empty, do: %__MODULE__{}

  @doc "Fully-qualified model module for `ref`, e.g. `Gcp.Storage.Model.Bucket`."
  def struct_name(%{namespace: ns}, ref), do: "#{ns}.Model.#{Macro.camelize(ref)}"

  @doc "Model module for the current anonymous-object prefix."
  def struct_name(context), do: struct_name(context, default_name(context))

  @doc "Typespec string for `ref`, e.g. `Gcp.Storage.Model.Bucket.t()`."
  def typespec(context, ref), do: struct_name(context, ref) <> ".t()"

  @doc "Typespec for the current anonymous-object prefix."
  def typespec(context), do: typespec(context, default_name(context))

  defp default_name(%{property: p}) when p in ["", nil], do: "Unknown"
  defp default_name(%{property: p}), do: Macro.camelize(p)

  def with_namespace(context, namespace), do: %{context | namespace: namespace}
  def with_base_path(context, base_path), do: %{context | base_path: path(context, base_path)}
  def with_models_by_name(context, models), do: %{context | models_by_name: models}

  @doc "Descends into a nested property, extending the naming prefix."
  def with_property(context, property) do
    %{context | property: "#{context.property}#{Macro.camelize(property)}"}
  end

  @doc "Name for an (possibly anonymous) schema under the current prefix."
  def name(context, name), do: "#{context.property}#{Macro.camelize(name)}"

  @doc "Joins a path suffix onto the context base path."
  def path(_, "/" <> suffix), do: suffix
  def path(%{base_path: nil}, suffix), do: suffix
  def path(%{base_path: base}, suffix), do: Path.join([base, suffix])
end
