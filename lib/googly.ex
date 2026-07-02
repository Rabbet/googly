defmodule Googly do
  @moduledoc """
  Generates modern, self-contained Elixir clients for any Google API from its
  discovery document. Built on Req + Jason.
  """

  alias Googly.ApiConfig
  alias Googly.Discovery
  alias Googly.Generator

  @doc "Downloads and caches the discovery document for `config`."
  defdelegate fetch(config), to: Discovery

  @doc "Generates the client package for `config` from its cached discovery doc."
  defdelegate generate(config), to: Generator

  @doc "Fetches (if needed), generates, and formats the client for `config`."
  def build(%ApiConfig{} = config) do
    with {:ok, _path} <- ensure_fetched(config),
         :ok <- Generator.generate(config) do
      format(config)
      {:ok, ApiConfig.client_dir(config)}
    end
  end

  defp ensure_fetched(config) do
    if File.exists?(ApiConfig.spec_file(config)),
      do: {:ok, :cached},
      else: Discovery.fetch(config)
  end

  defp format(config) do
    Mix.Task.rerun("format", ["#{ApiConfig.client_dir(config)}/**/*.{ex,exs}"])
  end
end
