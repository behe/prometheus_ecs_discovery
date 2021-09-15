defmodule PrometheusEcsDiscovery.MixProject do
  use Mix.Project

  def project do
    [
      app: :prometheus_ecs_discovery,
      version: "0.1.0",
      elixir: "~> 1.12",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      preferred_cli_env: ["test.watch": :test]
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {PrometheusEcsDiscovery.Application, []}
    ]
  end

  defp deps do
    [
      {:ex_aws_ecs, "~> 0.1"},
      {:ex_aws_ec2, "~> 2.0"},
      {:hammox, "~> 0.2", only: :test},
      {:httpoison, "~> 1.0"},
      {:jason, "~> 1.0"},
      {:mix_test_watch, "~> 1.0", only: :test}
    ]
  end
end
