defmodule PrometheusEcsDiscovery.Worker do
  use GenServer

  def init(init_arg) do
    Process.send_after(self(), :poll, 50)
    {:ok, init_arg}
  end

  def start_link(args) do
    GenServer.start_link(__MODULE__, args)
  end

  def handle_info(:poll, state) do
    Process.send_after(self(), :poll, 1000 * 60)
    PrometheusEcsDiscovery.disco()

    {:noreply, state}
  end

  def handle_info(_, state) do
    {:noreply, state}
  end
end
