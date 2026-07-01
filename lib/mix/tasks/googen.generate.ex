defmodule Mix.Tasks.Googen.Generate do
  @shortdoc "Generate client packages for configured APIs"
  @moduledoc """
  Fetches (if needed), generates, and formats clients.

      mix googen.generate            # all configured APIs
      mix googen.generate Storage    # just one
  """
  use Mix.Task

  alias Googen.ApiConfig

  @impl true
  def run(args) do
    Application.ensure_all_started(:req)

    configs =
      if args == [], do: ApiConfig.load_all(), else: Enum.flat_map(args, &ApiConfig.load/1)

    Enum.each(configs, fn config ->
      case Googen.build(config) do
        {:ok, dir} -> Mix.shell().info("Generated #{config.name} -> #{dir}")
        {:error, reason} -> Mix.shell().error("Failed #{config.name}: #{inspect(reason)}")
      end
    end)
  end
end
