defmodule Googen.GeneratorTest do
  # Not async: generates a client into a tmp dir and compiles it into the VM.
  use ExUnit.Case, async: false

  # These modules are generated and compiled at runtime in setup_all, so the
  # compiler can't see them when this test file is compiled.
  @compile {:no_warn_undefined, [Gcp.Widget.Model.Widget, Gcp.Widget.Widgets]}

  alias Googen.ApiConfig
  alias Googen.Generator

  setup_all do
    tmp = Path.join(System.tmp_dir!(), "googen_e2e_#{System.unique_integer([:positive])}")
    specs = Path.join(tmp, "specs")
    clients = Path.join(tmp, "clients")
    File.mkdir_p!(specs)
    File.cp!("test/fixtures/widget-v1.json", Path.join(specs, "Widget-v1.json"))

    previous = {
      Application.get_env(:googen, :clients_dir),
      Application.get_env(:googen, :specs_dir)
    }

    Application.put_env(:googen, :clients_dir, clients)
    Application.put_env(:googen, :specs_dir, specs)

    :ok = Generator.generate(%ApiConfig{name: "Widget", version: "v1", url: "unused"})
    compile_client(Path.join([clients, "gcp_widget", "lib", "gcp", "widget"]))

    on_exit(fn ->
      {prev_clients, prev_specs} = previous
      Application.put_env(:googen, :clients_dir, prev_clients)
      Application.put_env(:googen, :specs_dir, prev_specs)
      File.rm_rf!(tmp)
    end)

    {:ok, root: Path.join(clients, "gcp_widget")}
  end

  test "produces the package scaffolding", %{root: root} do
    for file <- ~w(mix.exs README.md LICENSE) do
      assert File.exists?(Path.join(root, file)), "missing #{file}"
    end
  end

  # The generated modules only exist at runtime (compiled in setup_all), so
  # structs are referenced dynamically — no compile-time `%Module{}` literals.
  test "decode/1 builds nested typed structs from a JSON map" do
    widget =
      Gcp.Widget.Model.Widget.decode(%{
        "name" => "w",
        "createdAt" => "2024-01-01T00:00:00Z",
        "satisfiesPZS" => true,
        "owner" => %{"email" => "a@b.c"},
        "parts" => [%{"sku" => "x"}, %{"sku" => "y"}],
        "tags" => ["red", "blue"],
        "labels" => %{"env" => "prod"},
        "config" => %{"maxItems" => 3}
      })

    assert widget.name == "w"
    assert widget.created_at == ~U[2024-01-01 00:00:00Z]
    assert widget.satisfies_pzs == true
    assert widget.tags == ["red", "blue"]
    assert widget.labels == %{"env" => "prod"}

    assert widget.owner.__struct__ == Gcp.Widget.Model.Owner
    assert widget.owner.email == "a@b.c"

    assert Enum.map(widget.parts, & &1.sku) == ["x", "y"]
    assert Enum.all?(widget.parts, &(&1.__struct__ == Gcp.Widget.Model.Part))

    assert widget.config.__struct__ == Gcp.Widget.Model.WidgetConfig
    assert widget.config.max_items == 3
  end

  test "Jason.encode! drops nils and maps snake keys back to wire names" do
    widget =
      struct(Gcp.Widget.Model.Widget,
        name: "w",
        satisfies_pzs: true,
        created_at: ~U[2024-01-01 00:00:00Z]
      )

    assert Jason.decode!(Jason.encode!(widget)) == %{
             "name" => "w",
             "satisfiesPZS" => true,
             "createdAt" => "2024-01-01T00:00:00Z"
           }
  end

  test "a generated API call builds the right request and decodes the response" do
    parent = self()

    adapter = fn request ->
      send(parent, {:captured, request.method, URI.to_string(request.url)})
      {request, %Req.Response{status: 200, body: %{"name" => "w1"}}}
    end

    assert {:ok, widget} =
             Gcp.Widget.Widgets.get("w1", token: "tok", fields: "name", req: [adapter: adapter])

    assert widget.__struct__ == Gcp.Widget.Model.Widget
    assert widget.name == "w1"

    assert_received {:captured, :get, url}
    assert url =~ "https://widget.googleapis.com/widget/v1/widgets/w1"
  end

  test "caller :req params merge with generated params instead of crashing" do
    parent = self()

    adapter = fn request ->
      send(parent, {:url, URI.to_string(request.url)})
      {request, %Req.Response{status: 200, body: %{"name" => "w"}}}
    end

    assert {:ok, _} =
             Gcp.Widget.Widgets.get("w1",
               fields: "name",
               token: "tok",
               req: [adapter: adapter, params: [extra: "1"]]
             )

    # both the generated `fields` param and the caller's `extra` param survive
    assert_received {:url, url}
    assert url =~ "fields=name"
    assert url =~ "extra=1"
  end

  test "media detection follows the merged alt param, not just the generated one" do
    json = fn request ->
      {request,
       %Req.Response{
         status: 200,
         headers: %{"content-type" => ["application/json"]},
         body: ~s({"name":"w"})
       }}
    end

    # caller forces alt=media via :req params -> raw bytes, no decoding
    assert {:ok, body} =
             Gcp.Widget.Widgets.get("w1", token: "t", req: [adapter: json, params: [alt: "media"]])

    assert body == ~s({"name":"w"})

    # caller overrides a generated alt=media back to alt=json -> decoded struct
    assert {:ok, widget} =
             Gcp.Widget.Widgets.get("w1",
               alt: "media",
               token: "t",
               req: [adapter: json, params: [alt: "json"]]
             )

    assert widget.__struct__ == Gcp.Widget.Model.Widget
  end

  test "error responses come back as the client's Error struct" do
    adapter = fn request ->
      {request,
       %Req.Response{status: 404, body: %{"error" => %{"code" => 404, "message" => "nope"}}}}
    end

    assert {:error, error} =
             Gcp.Widget.Widgets.get("missing", token: "tok", req: [adapter: adapter])

    assert error.__struct__ == Gcp.Widget.Error
    assert error.status == 404
    assert error.code == 404
    assert error.message == "nope"
  end

  test "alt=media returns raw bytes even when the body is application/json" do
    adapter = fn request ->
      {request,
       %Req.Response{
         status: 200,
         headers: %{"content-type" => ["application/json"]},
         body: ~s({"stored":"json"})
       }}
    end

    assert {:ok, body} =
             Gcp.Widget.Widgets.get("w1", alt: "media", token: "tok", req: [adapter: adapter])

    # raw bytes, not JSON-decoded to a map and not built into a struct
    assert body == ~s({"stored":"json"})
  end

  test "multipart streams a File.Stream from disk with a computed content-length" do
    path = Path.join(System.tmp_dir!(), "googen_upload_#{System.unique_integer([:positive])}.bin")
    File.write!(path, String.duplicate("x", 1000))
    on_exit(fn -> File.rm(path) end)

    parent = self()

    adapter = fn request ->
      send(parent, {:upload, request.headers, request.body})
      {request, %Req.Response{status: 200, body: %{"name" => "ok"}}}
    end

    metadata = struct(Gcp.Widget.Model.Widget, name: "obj")

    assert {:ok, _} =
             Gcp.Widget.Widgets.insert_multipart(metadata, File.stream!(path),
               token: "tok",
               content_type: "application/octet-stream",
               req: [adapter: adapter]
             )

    assert_received {:upload, headers, body}
    bytes = body |> Enum.to_list() |> IO.iodata_to_binary()
    # content-length is set and matches the fully-assembled multipart body
    assert [length] = headers["content-length"]
    assert String.to_integer(length) == byte_size(bytes)
    assert String.contains?(bytes, String.duplicate("x", 1000))
  end

  test "a size-less stream is rejected (Google uploads require a content-length)" do
    stream = Stream.cycle(["x"]) |> Stream.take(3)

    assert_raise ArgumentError, ~r/iodata or a File\.Stream/, fn ->
      Gcp.Widget.Widgets.insert_media(stream, token: "tok")
    end
  end

  # Compiles the generated client into the VM. ParallelCompiler resolves the
  # cross-module references (models, runtime, the Jason.Encoder defimpl) as one
  # batch, so order doesn't matter and there are no "module not available" warnings.
  defp compile_client(lib_dir) do
    lib_dir
    |> Path.join("**/*.ex")
    |> Path.wildcard()
    |> Kernel.ParallelCompiler.compile(return_diagnostics: true)
  end
end
