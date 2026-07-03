defmodule Googly.Generator.InjectionTest do
  # A discovery document is untrusted input (googly generates a client for *any*
  # API). Values taken from it — schema, property, resource, and method names, and
  # the API `rootUrl` — land in generated *code* positions (`defmodule`,
  # `defstruct`, `def`, the `@base_url` module attribute), so a crafted value must
  # not be able to break out and inject executable Elixir.
  use ExUnit.Case, async: true

  alias Googly.Generator.Api
  alias Googly.Generator.Endpoint
  alias Googly.Generator.Model
  alias Googly.Generator.Property
  alias Googly.Generator.Renderer
  alias Googly.Generator.ResourceContext

  # Closes the `defmodule ... do` it lands in, runs code, then opens a second
  # module so the whole file still compiles — the PoC from the report.
  @payload "Evil do\n  raise \"pwned at compile time\"\nend\n\ndefmodule Sneaky do\n  def go, do: System.halt(1)"

  describe "name sanitization (source level)" do
    test "an injected schema name becomes a bare alias segment" do
      assert ResourceContext.name(ResourceContext.empty(), @payload) =~ ~r/^[A-Z][A-Za-z0-9]*$/
    end

    test "an injected `$ref` resolves to the same bare alias segment" do
      # define and reference must agree, or typespecs/decode point at nothing
      ns = ResourceContext.with_namespace(ResourceContext.empty(), "Googly.Test")

      assert ResourceContext.struct_name(ns, @payload) =~
               ~r/^Googly\.Test\.Model\.[A-Z][A-Za-z0-9]*$/
    end

    test "an injected property name becomes a bare identifier, wire preserved verbatim" do
      p = Property.from_schema(%{type: "string"}, @payload, ctx())
      assert p.name =~ ~r/^[a-z_][A-Za-z0-9_]*$/
      # the exact JSON wire name must survive untouched (it round-trips the API)
      assert p.wire == @payload
    end

    test "an injected method name becomes a bare function name" do
      [ep] =
        Endpoint.from_method(@payload, %{httpMethod: "GET", path: "w", parameters: %{}}, ctx())

      assert ep.name =~ ~r/^[a-z_][A-Za-z0-9_]*$/
    end

    test "an injected resource name renders as safe alias segments only" do
      # `resource_module` treats `.` as intentional module nesting (real nested
      # resources are dotted), so the guarantee is that *every* segment is a
      # bare alias — no segment can carry code.
      assert Renderer.resource_module("Googly.Test", @payload) =~
               ~r/^Googly\.Test(\.[A-Z][A-Za-z0-9]*)+$/
    end
  end

  describe "rendered code is inert (render level)" do
    test "a malicious schema name cannot inject a module body" do
      [model] =
        Model.from_schemas(%{
          @payload => %{type: "object", properties: %{"ok" => %{type: "string"}}}
        })

      src = Renderer.model(Model.put_properties(model, ctx()), "Googly.Test", "https://x/")
      assert_single_inert_module(src)
    end

    test "a malicious property name cannot inject into defstruct/@type/decode" do
      [model] =
        Model.from_schemas(%{
          "Widget" => %{type: "object", properties: %{@payload => %{type: "string"}}}
        })

      src = Renderer.model(Model.put_properties(model, ctx()), "Googly.Test", "https://x/")
      assert_single_inert_module(src)
    end

    test "a malicious method name cannot inject a function definition" do
      [ep] =
        Endpoint.from_method(@payload, %{httpMethod: "GET", path: "w", parameters: %{}}, ctx())

      api = %Api{name: "Widgets", description: "d", endpoints: [ep]}
      src = Renderer.api(api, "Googly.Test", [], "https://x/")
      assert_single_inert_module(src)
    end

    test "a malicious rootUrl cannot inject code into the @base_url attribute" do
      # `rootUrl` is taken verbatim from the (untrusted) discovery doc and becomes
      # the generated Request module's `@base_url` — a module attribute, evaluated
      # at COMPILE time. An Elixir string literal honours `#{...}`, so an
      # interpolation payload runs attacker code the moment the client compiles
      # (no need to even break out of the quotes). `~S` keeps the payload literal
      # here in the test rather than evaluating it.
      malicious_root = ~S|https://evil.example/#{raise "pwned at compile time"}|
      src = Renderer.request("Googly.Test", malicious_root)
      assert_inert_base_url(src, malicious_root)
    end
  end

  defp ctx do
    ResourceContext.empty()
    |> ResourceContext.with_namespace("Googly.Test")
    |> ResourceContext.with_models_by_name(%{})
  end

  # The rendered source must parse, define exactly one module, and contain no
  # `raise` call node — the payload's marker for "attacker code reached a code
  # position." A parse failure means the injection at least broke out of its
  # slot, which is also a failure.
  defp assert_single_inert_module(src) do
    ast =
      case Code.string_to_quoted(src) do
        {:ok, ast} ->
          ast

        {:error, err} ->
          flunk(
            "generated source did not parse (injection escaped its slot): #{inspect(err)}\n\n#{src}"
          )
      end

    assert count_nodes(ast, :defmodule) == 1, "expected exactly one module:\n\n#{src}"
    assert count_nodes(ast, :raise) == 0, "an injected `raise` reached a code position:\n\n#{src}"
  end

  defp count_nodes(ast, fun) do
    {_, count} =
      Macro.prewalk(ast, 0, fn
        {^fun, _, _} = node, acc -> {node, acc + 1}
        node, acc -> {node, acc}
      end)

    count
  end

  # The generated `@base_url` must parse to an inert string *literal* — a plain
  # binary the URL library later reads as data. If the value is anything else (an
  # interpolation `{:<<>>, ...}` node, injected sibling code, or an unparseable
  # breakout), the discovery `rootUrl` reached a code position and can execute at
  # compile time. A string literal categorically cannot, and must round-trip the
  # exact `rootUrl` so the client still targets the right host.
  defp assert_inert_base_url(src, expected) do
    ast =
      case Code.string_to_quoted(src) do
        {:ok, ast} ->
          ast

        {:error, err} ->
          flunk(
            "generated Request did not parse (rootUrl escaped its slot): #{inspect(err)}\n\n#{src}"
          )
      end

    values =
      Macro.prewalk(ast, [], fn
        {:@, _, [{:base_url, _, [value]}]} = node, acc -> {node, [value | acc]}
        node, acc -> {node, acc}
      end)
      |> elem(1)

    assert [value] = values, "expected exactly one @base_url attribute:\n\n#{src}"

    assert is_binary(value),
           "@base_url is not an inert string literal — rootUrl reached a code position:\n\n#{src}"

    assert value == expected, "the exact rootUrl must round-trip untouched:\n\n#{src}"
  end
end
