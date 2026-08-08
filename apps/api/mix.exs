defmodule MilosTraining.MixProject do
  use Mix.Project

  def project do
    [
      app: :milos_training,
      version: "0.1.0",
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      listeners: [Phoenix.CodeReloader],
      aliases: aliases(),
      deps: deps(),
      dialyzer: [
        plt_add_deps: :apps_direct,
        plt_add_apps: [:ecto, :ex_unit, :mix, :phoenix_pubsub, :plug, :telemetry],
        ignore_warnings: ".dialyzer_ignore.exs"
      ]
    ]
  end

  def application do
    [
      mod: {MilosTraining.Application, []},
      extra_applications: [
        :logger,
        :runtime_tools,
        :os_mon,
        :opentelemetry_exporter,
        :opentelemetry
      ]
    ]
  end

  def cli do
    [
      preferred_envs: [precommit: :test]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:phoenix, "~> 1.8.1"},
      {:phoenix_ecto, "~> 4.5"},
      {:ecto_sql, "~> 3.13"},
      {:postgrex, "~> 0.22.4"},
      {:phoenix_live_dashboard, "~> 0.8.3"},
      {:swoosh, "~> 1.16"},
      {:req, "~> 0.7.2"},
      {:castore, "~> 1.0.20"},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},
      {:opentelemetry, "~> 1.5"},
      {:opentelemetry_api, "~> 1.4"},
      {:opentelemetry_exporter, "~> 1.8"},
      {:opentelemetry_phoenix, "~> 2.0"},
      {:opentelemetry_ecto, "~> 1.2"},
      {:opentelemetry_bandit, "~> 0.2"},
      {:gettext, "~> 0.26"},
      {:tz, "~> 0.28"},
      {:jason, "~> 1.2"},
      {:open_api_spex, "~> 3.18"},
      {:oban, "~> 2.22.1"},
      {:guardian, "~> 2.4.1"},
      {:argon2_elixir, "~> 4.0"},
      {:ex_rated, "~> 2.1"},
      {:redix, "~> 1.3"},
      {:web_push_elixir, "~> 0.8.0"},
      {:dns_cluster, "~> 0.2.0"},
      {:bandit, "~> 1.12.4"},
      {:ex_aws, "~> 2.5"},
      {:ex_aws_s3, "~> 2.5"},
      {:hackney, "~> 4.7.2"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get", "ecto.setup"],
      "ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"],
      precommit: [
        "cmd node scripts/validate_gettext_catalogs.mjs",
        "compile --warning-as-errors",
        "milos.architecture",
        "credo --strict",
        "dialyzer --list-unused-filters",
        "deps.unlock --check-unused",
        "format --check-formatted",
        "test"
      ]
    ]
  end
end
