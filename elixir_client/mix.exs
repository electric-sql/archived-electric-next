defmodule Electric.Client.MixProject do
  use Mix.Project

  def project do
    [
      app: :electric_client,
      version: "0.1.0",
      elixir: "~> 1.17",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:gen_stage, "~> 1.2"},
      {:jaxon, "~> 2.0"},
      {:qex, "~> 0.5"},
      {:postgrex, "~> 0.18", only: [:test]},
      {:postgresql_uri, "~> 0.1", only: [:test]},
      {:req, "~> 0.5"},
      {:typed_struct, "~> 0.3"},
      {:uuid, "~> 1.1", only: [:test]}
    ]
  end
end
