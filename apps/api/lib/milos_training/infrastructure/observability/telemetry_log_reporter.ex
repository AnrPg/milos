defmodule MilosTraining.Infrastructure.Observability.TelemetryLogReporter do
  use GenServer

  require Logger

  @events [
    [:phoenix, :endpoint, :stop],
    [:phoenix, :router_dispatch, :stop],
    [:phoenix, :router_dispatch, :exception],
    [:phoenix, :channel_joined],
    [:phoenix, :channel_handled_in],
    [:milos_training, :repo, :query],
    [:milos, :communication, :message_recorded],
    [:milos, :runtime]
  ]

  def start_link(options), do: GenServer.start_link(__MODULE__, options, name: __MODULE__)

  @impl true
  def init(options) do
    :ok = :telemetry.attach_many(__MODULE__, @events, &__MODULE__.handle_event/4, nil)
    interval = Keyword.get(options, :report_interval, 60_000)
    Process.send_after(self(), :report, interval)
    {:ok, %{interval: interval, aggregates: %{}}}
  end

  def handle_event(event, measurements, metadata, _config) do
    GenServer.cast(__MODULE__, {:measurement, event, measurements, metadata})
  end

  @impl true
  def handle_cast({:measurement, event, measurements, metadata}, state) do
    tags =
      metadata
      |> Map.take([:route, :event, :result, :queue])
      |> Enum.reduce(%{}, fn {key, value}, tags ->
        case normalize_tag(value) do
          {:ok, normalized} -> Map.put(tags, key, normalized)
          :drop -> tags
        end
      end)

    aggregates =
      Enum.reduce(measurements, state.aggregates, fn
        {measurement, value}, aggregates when is_number(value) ->
          key = {Enum.join(event ++ [measurement], "."), tags}
          aggregate = Map.get(aggregates, key, %{count: 0, sum: 0, max: value})

          Map.put(aggregates, key, %{
            count: aggregate.count + 1,
            sum: aggregate.sum + value,
            max: max(aggregate.max, value)
          })

        {_measurement, _value}, aggregates ->
          aggregates
      end)

    {:noreply, %{state | aggregates: aggregates}}
  end

  @impl true
  def handle_info(:report, state) do
    payload =
      Enum.map(state.aggregates, fn {{metric, tags}, values} ->
        %{metric: metric, tags: tags, count: values.count, sum: values.sum, max: values.max}
      end)

    if payload != [], do: Logger.info("telemetry_summary=#{Jason.encode!(payload)}")
    Process.send_after(self(), :report, state.interval)
    {:noreply, %{state | aggregates: %{}}}
  end

  @impl true
  def terminate(_reason, _state) do
    :telemetry.detach(__MODULE__)
    :ok
  end

  defp normalize_tag(value) when is_binary(value) or is_number(value) or is_boolean(value),
    do: {:ok, value}

  defp normalize_tag(value) when is_atom(value), do: {:ok, Atom.to_string(value)}
  defp normalize_tag(_value), do: :drop
end
