defmodule Googly.MixProject do
  use Mix.Project

  def project do
    [
      app: :googly,
      version: "0.1.0",
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      # Generated Jason.Encoder impls are compiled at runtime in the end-to-end
      # test, so protocols must stay extensible there.
      consolidate_protocols: Mix.env() != :test,
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:req, "~> 0.6"},
      {:jason, "~> 1.4"}
    ]
  end
end
