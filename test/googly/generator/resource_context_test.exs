defmodule Googly.Generator.ResourceContextTest do
  use ExUnit.Case, async: true

  alias Googly.Generator.ResourceContext

  test "struct_name/typespec for a ref" do
    assert ResourceContext.struct_name(ns(), "bucket") == "Googly.Widget.Model.Bucket"
    assert ResourceContext.typespec(ns(), "bucket") == "Googly.Widget.Model.Bucket.t()"
  end

  test "with_property builds a camelCase-accumulating prefix used to name inline objects" do
    context =
      ns()
      |> ResourceContext.with_property("bucket")
      |> ResourceContext.with_property("objectRetention")

    assert ResourceContext.name(context, "policy") == "BucketObjectRetentionPolicy"
    # the anonymous-object struct name uses that prefix
    assert ResourceContext.struct_name(context) == "Googly.Widget.Model.BucketObjectRetention"
  end

  describe "path/2" do
    test "an absolute path drops the base path" do
      context = ResourceContext.with_base_path(ns(), "widget/v1/")
      assert ResourceContext.path(context, "/upload/x") == "upload/x"
    end

    test "a relative path is joined onto the base path" do
      context = ResourceContext.with_base_path(ns(), "widget/v1/")
      assert ResourceContext.path(context, "widgets/{id}") == "widget/v1/widgets/{id}"
    end
  end

  defp ns, do: ResourceContext.with_namespace(ResourceContext.empty(), "Googly.Widget")
end
