defmodule Googen.Discovery do
  @moduledoc """
  Fetches Google API discovery documents and caches them under `specs_dir`.
  """

  require Logger
  alias Googen.ApiConfig

  @doc """
  Downloads the discovery document for `config` and writes it to its spec file.
  Returns `{:ok, path}` or `{:error, reason}`.
  """
  @spec fetch(ApiConfig.t()) :: {:ok, Path.t()} | {:error, term}
  def fetch(%ApiConfig{url: url} = config) do
    path = ApiConfig.spec_file(config)
    Logger.info("Fetching #{config.name} #{config.version} from #{url}")

    with {:ok, %{status: 200, body: body}} <- Req.get(url, decode_body: false),
         :ok <- File.mkdir_p(Path.dirname(path)),
         :ok <- File.write(path, body) do
      {:ok, path}
    else
      {:ok, %{status: status}} -> {:error, "discovery returned HTTP #{status}"}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Lists every public Google API from the Discovery service as
  `[%{name, version, url}]`. Handy for discovering new APIs to add to
  `config/apis.json`.
  """
  @spec list(keyword) :: {:ok, [map]} | {:error, term}
  def list(opts \\ []) do
    params = if Keyword.get(opts, :preferred, true), do: [preferred: true], else: []

    case Req.get("https://discovery.googleapis.com/discovery/v1/apis", params: params) do
      {:ok, %{status: 200, body: %{"items" => items}}} ->
        {:ok,
         Enum.map(items, fn item ->
           %{name: item["name"], version: item["version"], url: item["discoveryRestUrl"]}
         end)}

      {:ok, %{status: status}} ->
        {:error, "discovery list returned HTTP #{status}"}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
