defmodule Mix.Tasks.Googly.Release do
  @shortdoc "Bump versions and publish generated clients to Hex"
  @moduledoc """
  Bumps each client's version and publishes it to Hex (package + docs).

      HEX_API_KEY=... mix googly.release               # all configured clients
      HEX_API_KEY=... mix googly.release CloudStorage  # just one
      mix googly.release --minor                       # minor bump (default: patch)
      mix googly.release --no-bump                     # publish current versions as-is

  Run `mix googly.generate` first so the client source is current, review the
  diff, and commit the regenerated + version-bumped output alongside the release.
  The version lives in each client's `mix.exs` and is preserved across
  regenerations, so bumps stick.
  """
  use Mix.Task

  alias Googly.ApiConfig

  @impl true
  def run(args) do
    {opts, names} =
      OptionParser.parse!(args, strict: [minor: :boolean, patch: :boolean, no_bump: :boolean])

    bump =
      cond do
        opts[:no_bump] -> nil
        opts[:minor] -> :minor
        true -> :patch
      end

    configs = if names == [], do: ApiConfig.load_all(), else: Enum.flat_map(names, &ApiConfig.load/1)
    Enum.each(configs, &release(&1, bump))
  end

  defp release(config, bump) do
    dir = ApiConfig.client_dir(config)
    if bump, do: bump_version(dir, bump)

    Mix.shell().info("Publishing #{ApiConfig.package_name(config)} from #{dir}")
    run!(dir, ["deps.get"])
    run!(dir, ["hex.publish", "--yes"])
  end

  defp bump_version(dir, kind) do
    path = Path.join(dir, "mix.exs")
    content = File.read!(path)
    [_, current] = Regex.run(~r/@version "([\d.]+)"/, content)
    next = next_version(current, kind)
    File.write!(path, Regex.replace(~r/@version "[\d.]+"/, content, ~s(@version "#{next}")))
    Mix.shell().info("#{Path.basename(dir)}: #{current} -> #{next}")
  end

  defp next_version(current, kind) do
    version = Version.parse!(current)

    case kind do
      :minor -> %{version | minor: version.minor + 1, patch: 0}
      :patch -> %{version | patch: version.patch + 1}
    end
    |> to_string()
  end

  defp run!(dir, args) do
    {out, status} = System.cmd("mix", args, cd: dir, stderr_to_stdout: true)
    Mix.shell().info(out)
    if status != 0, do: Mix.raise("`mix #{Enum.join(args, " ")}` failed in #{dir}")
  end
end
