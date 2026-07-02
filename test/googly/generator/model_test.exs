defmodule Googly.Generator.ModelTest do
  use ExUnit.Case, async: true

  alias Googly.Generator.Model
  alias Googly.Generator.ResourceContext

  test "collects top-level schemas and names inline objects by their nesting path" do
    names = models() |> Enum.map(& &1.name) |> Enum.sort()
    # `config` is an inline object on Widget -> WidgetConfig
    assert names == ["Owner", "Part", "Widget", "WidgetConfig"]
  end

  test "filename underscores the model name" do
    assert Model.filename(%Model{name: "WidgetConfig"}) == "widget_config.ex"
  end

  test "an array-typed schema is flagged is_array" do
    schemas = %{
      "Things" => %{type: "array", items: %{type: "object", properties: %{x: %{type: "string"}}}}
    }

    assert %Model{is_array: true} =
             schemas |> Model.from_schemas() |> by_name() |> Map.fetch!("Things")
  end

  describe "put_properties" do
    setup do
      context =
        ResourceContext.empty()
        |> ResourceContext.with_namespace("Googly.Widget")
        |> ResourceContext.with_models_by_name(by_name(models()))

      widget = models() |> by_name() |> Map.fetch!("Widget")
      props = Model.put_properties(widget, context).properties |> Map.new(&{&1.name, &1})
      {:ok, props: props}
    end

    test "properties are snake_cased with the exact wire name preserved", %{props: props} do
      assert props["created_at"].wire == "createdAt"
      assert props["satisfies_pzs"].wire == "satisfiesPZS"
      assert props["name"].wire == "name"
    end

    test "types resolve against the model set", %{props: props} do
      assert props["created_at"].type.decode == :datetime
      assert props["owner"].type.decode == {:struct, "Googly.Widget.Model.Owner"}
      assert props["parts"].type.decode == {:struct, "Googly.Widget.Model.Part"}
      assert props["parts"].type.typespec == "list(Googly.Widget.Model.Part.t())"
      assert props["tags"].type.typespec == "list(String.t())"
      assert props["labels"].type.typespec == "map()"
      assert props["size"].type.typespec == "integer()"
      # the inline object points at its generated model
      assert props["config"].type.decode == {:struct, "Googly.Widget.Model.WidgetConfig"}
    end
  end

  defp schemas do
    "test/fixtures/widget-v1.json"
    |> File.read!()
    |> Jason.decode!(keys: :atoms)
    |> Map.fetch!(:schemas)
  end

  defp models, do: Model.from_schemas(schemas())

  defp by_name(models), do: Map.new(models, &{&1.name, &1})
end
