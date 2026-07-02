defmodule Googly.ApiConfigTest do
  use ExUnit.Case, async: true

  alias Googly.ApiConfig

  describe "naming derivation" do
    test "package_name snake-cases with a googly_ prefix" do
      assert ApiConfig.package_name(config("Storage")) == "googly_storage"
      assert ApiConfig.package_name(config("DocumentAI")) == "googly_document_ai"
    end

    test "module_root keeps the name verbatim under Googly" do
      assert ApiConfig.module_root(config("Storage")) == "Googly.Storage"
      # DocumentAI must not be mangled to DocumentAi
      assert ApiConfig.module_root(config("DocumentAI")) == "Googly.DocumentAI"
    end

    test "spec_file and client_dir" do
      assert ApiConfig.spec_file(config("Storage")) =~ "Storage-v1.json"
      assert ApiConfig.client_dir(config("Storage")) =~ "googly_storage"
    end
  end

  describe "load_all/0" do
    test "parses config/apis.json into structs with all fields set" do
      configs = ApiConfig.load_all()

      assert length(configs) > 0

      assert Enum.all?(configs, fn c ->
               match?(%ApiConfig{}, c) and is_binary(c.name) and is_binary(c.version) and
                 is_binary(c.url)
             end)
    end

    test "load/1 filters by name" do
      assert [%ApiConfig{name: "CloudStorage"}] = ApiConfig.load("CloudStorage")
      assert [] = ApiConfig.load("Nonexistent")
    end
  end

  defp config(name, version \\ "v1"),
    do: %ApiConfig{name: name, version: version, url: "https://example.com"}
end
