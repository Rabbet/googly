defmodule Mix.Tasks.Googly.Discover do
  @shortdoc "List Google APIs available from the Discovery service"
  @moduledoc """
  Prints every public Google API (name, version, discovery URL) so you can pick
  ones to add to `config/apis.json`.

      mix googly.discover           # all preferred APIs
      mix googly.discover storage   # filter by substring
  """
  use Mix.Task

  @impl true
  def run(args) do
    Application.ensure_all_started(:req)
    filter = List.first(args)

    case Googly.Discovery.list() do
      {:ok, items} ->
        items
        |> maybe_filter(filter)
        |> Enum.each(fn i -> Mix.shell().info("#{i.name} #{i.version}\t#{i.url}") end)

      {:error, reason} ->
        Mix.shell().error("Discovery failed: #{inspect(reason)}")
    end
  end

  defp maybe_filter(items, nil), do: items

  defp maybe_filter(items, filter) do
    f = String.downcase(filter)
    Enum.filter(items, &String.contains?(String.downcase(&1.name), f))
  end
end
