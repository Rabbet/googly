defmodule Googly.Generator.ParameterTest do
  use ExUnit.Case, async: true

  alias Googly.Generator.Parameter
  alias Googly.Generator.ResourceContext

  describe "from_method/2" do
    test "splits required (ordered by parameterOrder) from optional" do
      method = %{
        path: "widgets/{widgetId}",
        parameterOrder: ["widgetId"],
        parameters: %{
          widgetId: %{type: "string", location: "path", required: true},
          fields: %{type: "string", location: "query"}
        }
      }

      assert {[%Parameter{name: "widget_id", location: "path"}],
              [%Parameter{name: "fields", location: "query"}]} =
               Parameter.from_method(method, ctx())
    end

    test "appends a body param when the method has a request" do
      method = %{path: "widgets", parameters: nil, request: %{"$ref": "Widget"}}

      assert {[], [%Parameter{name: "body", location: "body"}]} =
               Parameter.from_method(method, ctx())
    end

    test "camelCase params become snake_case variables with the wire name preserved" do
      method = %{path: "x", parameters: %{maxResults: %{type: "integer", location: "query"}}}
      assert {[], [param]} = Parameter.from_method(method, ctx())
      assert param.name == "max_results"
      assert param.variable_name == "max_results"
      assert param.wire == "maxResults"
    end

    test "a {+name} reserved-expansion path param preserves slashes" do
      method = %{
        path: "v1/{+name}:process",
        parameterOrder: ["name"],
        parameters: %{name: %{type: "string", location: "path", required: true}}
      }

      assert {[param], []} = Parameter.from_method(method, ctx())
      assert param.reserved?
    end

    test "a simple {object} path param is not reserved (its slashes are percent-encoded)" do
      assert {[param], []} = Parameter.from_method(object_method(), ctx())
      refute param.reserved?
    end
  end

  test "from_method_param sanitizes odd wire names like $.xgafv" do
    param = Parameter.from_method_param("$.xgafv", %{type: "string", location: "query"}, ctx())
    assert param.name == "xgafv"
    assert param.wire == "$.xgafv"
  end

  defp ctx, do: ResourceContext.with_namespace(ResourceContext.empty(), "Googly.Widget")

  defp object_method do
    %{
      path: "b/{bucket}/o/{object}",
      parameterOrder: ["object"],
      parameters: %{object: %{type: "string", location: "path", required: true}}
    }
  end
end
