defmodule Mix.Tasks.Googly.Release do
  @shortdoc "Bump client versions and print the Hex publish commands"
  @moduledoc """
  Bumps each client's version and prints the `mix hex.publish` command for each
  package. Publishing itself is left to you to run.

      mix googly.release               # patch-bump every client, print publish cmds
      mix googly.release CloudStorage  # just one
      mix googly.release --minor       # minor bump (default: patch)
      mix googly.release --no-bump     # don't bump; just print the publish commands

  Publishing is manual on purpose: `mix hex.publish` needs a real terminal for
  Hex's passphrase and 2FA prompts, which a Mix-spawned subprocess can't provide.
  So this task automates the tedious part (bumping every package in lockstep) and
  hands you the commands to run in your shell.

  Typical flow:

      mix googly.generate            # refresh from discovery
      mix googly.release             # bump versions + print publish commands
      git add . && git commit        # commit the regenerated + bumped output
      # then run each printed `mix hex.publish` yourself

  Versions live in each client's `mix.exs` and are preserved across
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

    configs =
      if names == [], do: ApiConfig.load_all(), else: Enum.flat_map(names, &ApiConfig.load/1)

    dirs =
      Enum.map(configs, fn config ->
        dir = ApiConfig.client_dir(config)
        if bump, do: bump_version(dir, bump)
        dir
      end)

    print_publish_commands(dirs)
  end

  defp print_publish_commands(dirs) do
    Mix.shell().info(
      "\nCommit the changes, then publish each package (Hex prompts for passphrase/2FA):\n"
    )

    Enum.each(dirs, &Mix.shell().info("    (cd #{&1} && mix hex.publish)"))
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
end
