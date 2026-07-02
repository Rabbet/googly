defmodule Googly.Generator.RendererTest do
  use ExUnit.Case, async: true

  alias Googly.Generator.Renderer

  describe "doc/2" do
    test "nil renders as empty string" do
      assert Renderer.doc(nil, 6) == ""
    end

    test "escapes triple quotes, interpolation and backslashes" do
      assert Renderer.doc(~s(a """ b), 0) == ~S(a \"\"\" b)
      assert Renderer.doc(~S(x #{y} z), 0) == ~S(x \#{y} z)
      assert Renderer.doc(~S(a\b), 0) == ~S(a\\b)
    end

    test "indents wrapped lines" do
      assert Renderer.doc("line1\nline2", 2) == "line1\n  line2"
    end
  end

  describe "wire_map/1" do
    test "includes only fields whose name differs from the wire" do
      model = %{properties: [prop("time_created", "timeCreated"), prop("name", "name")]}
      assert Renderer.wire_map(model) == ~s(%{time_created: "timeCreated"})
    end

    test "is empty when every field matches its wire name" do
      assert Renderer.wire_map(%{properties: [prop("name", "name")]}) == "%{}"
    end
  end

  describe "decode_rhs/1" do
    test "each decode strategy renders its call" do
      assert Renderer.decode_rhs(decodable("name", :raw)) == ~s|m["name"]|

      assert Renderer.decode_rhs(decodable("createdAt", :datetime)) ==
               ~s|Decode.datetime(m["createdAt"])|

      assert Renderer.decode_rhs(decodable("day", :date)) == ~s|Decode.date(m["day"])|

      assert Renderer.decode_rhs(decodable("owner", {:struct, "M.Owner"})) ==
               ~s|M.Owner.decode(m["owner"])|

      assert Renderer.decode_rhs(decodable("ts", {:list, :datetime})) ==
               ~s|Decode.list(m["ts"], DateTime)|

      assert Renderer.decode_rhs(decodable("m", {:map, "M.Owner"})) ==
               ~s|Decode.map(m["m"], M.Owner)|
    end
  end

  describe "endpoint helpers" do
    test "signature_args yields positional args with a trailing comma, empty when none" do
      assert Renderer.signature_args(%{required_parameters: []}) == ""

      assert Renderer.signature_args(%{required_parameters: [var("bucket"), var("object")]}) ==
               "bucket, object, "
    end

    test "path_params URI-encodes, preserving slashes for reserved (`{+name}`) params" do
      ep = %{path_parameters: [path_param("bucket", false), path_param("name", true)]}

      assert Renderer.path_params(ep) ==
               ~s|"bucket" => URI.encode(bucket, &URI.char_unreserved?/1), | <>
                 ~s|"name" => URI.encode(name, &(URI.char_unreserved?(&1) or &1 == ?/))|
    end

    test "required_query emits {wire, var} tuples for required query params" do
      ep = %{required_parameters: [query_param("project"), path_param("bucket", false)]}
      assert Renderer.required_query(ep) == ~s({"project", project})
    end

    test "param_specs routes query and body params and dedupes by name" do
      ep = %{
        optional_parameters: [
          query_param("fields"),
          %{location: "body", name: "body", wire: "body"}
        ]
      }

      global = [query_param("alt")]

      assert Renderer.param_specs(ep, global) ==
               ~s(alt: {:query, "alt"}, fields: {:query, "fields"}, body: {:body, nil})
    end

    test "decode_target is the model module, or nil for raw/temporal returns" do
      assert Renderer.decode_target(
               %{return: %{struct: "Googly.Widget.Model.Widget"}},
               "Googly.Widget"
             ) ==
               "Googly.Widget.Model.Widget"

      assert Renderer.decode_target(%{return: %{struct: nil}}, "Googly.Widget") == "nil"
      assert Renderer.decode_target(%{return: %{struct: "DateTime"}}, "Googly.Widget") == "nil"
    end

    test "upload_type maps the upload kind" do
      assert Renderer.upload_type(%{upload: :media}) == "media"
      assert Renderer.upload_type(%{upload: :multipart}) == "multipart"
    end
  end

  defp prop(name, wire), do: %{name: name, wire: wire}

  defp decodable(wire, decode), do: %{wire: wire, type: %{decode: decode}}

  defp var(name), do: %{variable_name: name}

  defp path_param(name, reserved?),
    do: %{
      location: "path",
      type: %{name: "string"},
      variable_name: name,
      wire: name,
      reserved?: reserved?
    }

  defp query_param(name), do: %{location: "query", name: name, wire: name, variable_name: name}
end
