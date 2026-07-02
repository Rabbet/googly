defmodule Googly.Generator.EndpointTest do
  use ExUnit.Case, async: true

  alias Googly.Generator.Endpoint
  alias Googly.Generator.ResourceContext

  test "basic endpoint folds the service path and resolves the return type" do
    assert [ep] = Endpoint.from_method("get", get_method(), ctx())
    assert ep.name == "get"
    assert ep.method == :get
    assert ep.path == "/widget/v1/widgets/{widgetId}"
    assert ep.upload == nil
    assert [%{variable_name: "widget_id", location: "path"}] = ep.required_parameters
    assert ep.return.struct == "Googly.Widget.Model.Widget"
  end

  test "a media-upload method yields basic + media + multipart endpoints" do
    endpoints = Endpoint.from_method("insert", insert_method(), ctx())
    assert Enum.map(endpoints, & &1.name) == ["insert", "insert_media", "insert_multipart"]

    assert [_basic, media, multipart] = endpoints
    assert media.upload == :media
    assert multipart.upload == :multipart
    # upload variants post to the media path, not the service path
    assert media.path == "/upload/widget/v1/widgets"
    # media carries just `data`; multipart carries `metadata` then `data`
    assert List.last(media.required_parameters).variable_name == "data"
    assert Enum.map(multipart.required_parameters, & &1.variable_name) == ["metadata", "data"]
  end

  defp ctx do
    ResourceContext.empty()
    |> ResourceContext.with_namespace("Googly.Widget")
    |> ResourceContext.with_base_path("widget/v1/")
  end

  defp get_method do
    %{
      httpMethod: "GET",
      path: "widgets/{widgetId}",
      parameterOrder: ["widgetId"],
      parameters: %{widgetId: %{type: "string", location: "path", required: true}},
      response: %{"$ref": "Widget"}
    }
  end

  defp insert_method do
    %{
      httpMethod: "POST",
      path: "widgets",
      request: %{"$ref": "Widget"},
      response: %{"$ref": "Widget"},
      supportsMediaUpload: true,
      mediaUpload: %{protocols: %{simple: %{path: "/upload/widget/v1/widgets"}}}
    }
  end
end
