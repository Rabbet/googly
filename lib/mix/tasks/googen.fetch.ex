defmodule Mix.Tasks.Googen.Fetch do
  @shortdoc "Download discovery documents for configured APIs"
  @moduledoc """
  Downloads and caches discovery documents.

      mix googen.fetch            # all configured APIs
      mix googen.fetch Storage    # just one
  """
  use Mix.Task

  alias Googen.ApiConfig

  @impl true
  def run(args) do
    Application.ensure_all_started(:req)

    configs =
      if args == [], do: ApiConfig.load_all(), else: Enum.flat_map(args, &ApiConfig.load/1)

    Enum.each(configs, fn config ->
      case Googen.fetch(config) do
        {:ok, path} -> Mix.shell().info("Fetched #{config.name} -> #{path}")
        {:error, reason} -> Mix.shell().error("Failed #{config.name}: #{inspect(reason)}")
      end
    end)
  end
end
