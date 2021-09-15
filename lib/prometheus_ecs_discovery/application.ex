defmodule PrometheusEcsDiscovery.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    [
      PrometheusEcsDiscovery.Worker
    ]
    |> Supervisor.start_link(strategy: :one_for_one, name: PrometheusEcsDiscovery.Supervisor)
  end
end
