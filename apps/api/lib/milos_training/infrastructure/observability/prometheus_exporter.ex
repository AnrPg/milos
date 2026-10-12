defmodule MilosTraining.Infrastructure.Observability.PrometheusExporter do
  @moduledoc """
  Aggregates `Telemetry.Metrics` definitions into an ETS table and renders them
  in the Prometheus text exposition format (version 0.0.4).

  Handlers write with atomic `:ets.update_counter/4` operations, so recording
  never serialises through this process. The GenServer only owns the table,
  attaches/detaches handlers, and renders scrapes.

  Supported metric types:

    * `counter/2`      -> Prometheus `counter` (`_total` suffix enforced)
    * `sum/2`          -> Prometheus `counter` (monotonic sum of the measurement)
    * `last_value/2`   -> Prometheus `gauge`
    * `distribution/2` -> Prometheus `histogram`; buckets come from
      `reporter_options[:buckets]`

  `reporter_options[:prometheus_name]` overrides the exported metric name.
  Sums are stored as integer micro-units so float measurements can still use
  atomic counters; six decimal places is ample precision for latency/bytes.
  """

  use GenServer

  alias Telemetry.Metrics.{Counter, Distribution, LastValue, Sum}

  @micro 1_000_000
  @default_buckets [0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10]

  def start_link(options) do
    name = Keyword.get(options, :name, __MODULE__)
    GenServer.start_link(__MODULE__, Keyword.put(options, :name, name), name: name)
  end

  def child_spec(options) do
    %{
      id: Keyword.get(options, :name, __MODULE__),
      start: {__MODULE__, :start_link, [options]}
    }
  end

  @doc "Renders the current metric state as Prometheus text exposition iodata."
  def scrape(server \\ __MODULE__), do: GenServer.call(server, :scrape)

  @impl true
  def init(options) do
    Process.flag(:trap_exit, true)
    name = Keyword.fetch!(options, :name)

    metrics =
      options
      |> Keyword.fetch!(:metrics)
      |> Enum.with_index(fn metric, index -> {index, metric} end)

    table = :ets.new(__MODULE__, [:set, :public, write_concurrency: true])
    handler_ids = attach_handlers(name, table, metrics)

    {:ok, %{table: table, metrics: metrics, handler_ids: handler_ids}}
  end

  @impl true
  def handle_call(:scrape, _from, state) do
    {:reply, Enum.map(state.metrics, &render_metric(&1, state.table)), state}
  end

  @impl true
  def terminate(_reason, state) do
    Enum.each(state.handler_ids, &:telemetry.detach/1)
    :ok
  end

  ## Recording

  defp attach_handlers(name, table, metrics) do
    metrics
    |> Enum.group_by(fn {_index, metric} -> metric.event_name end)
    |> Enum.map(fn {event_name, event_metrics} ->
      handler_id = {__MODULE__, name, event_name}
      # A killed exporter never runs terminate/2; detach stale handlers first.
      :telemetry.detach(handler_id)

      :ok =
        :telemetry.attach(handler_id, event_name, &__MODULE__.handle_event/4, %{
          table: table,
          metrics: event_metrics
        })

      handler_id
    end)
  end

  @doc false
  def handle_event(_event, measurements, metadata, %{table: table, metrics: metrics}) do
    Enum.each(metrics, fn {index, metric} ->
      safely_record(table, index, metric, measurements, metadata)
    end)
  end

  # A raising handler is permanently detached by :telemetry, which would
  # silently stop the metric. Unexpected metadata drops only that one sample.
  defp safely_record(table, index, metric, measurements, metadata) do
    if keep?(metric, measurements, metadata) do
      value = measurement_value(metric, measurements, metadata)
      record(metric, table, {index, labels(metric, metadata)}, value)
    end
  rescue
    _error -> :ok
  end

  defp keep?(%{keep: nil}, _measurements, _metadata), do: true

  defp keep?(%{keep: keep}, _measurements, metadata) when is_function(keep, 1),
    do: keep.(metadata)

  defp keep?(%{keep: keep}, measurements, metadata), do: keep.(metadata, measurements)

  defp measurement_value(%{measurement: fun}, measurements, _metadata) when is_function(fun, 1),
    do: fun.(measurements)

  defp measurement_value(%{measurement: fun}, measurements, metadata) when is_function(fun, 2),
    do: fun.(measurements, metadata)

  defp measurement_value(%{measurement: key}, measurements, _metadata),
    do: Map.get(measurements, key)

  defp labels(%{tags: []}, _metadata), do: []

  defp labels(metric, metadata) do
    tag_values = metric.tag_values.(metadata)
    Enum.map(metric.tags, &{Atom.to_string(&1), label_value(Map.get(tag_values, &1))})
  end

  defp label_value(nil), do: ""
  defp label_value(value) when is_binary(value), do: value
  defp label_value(value) when is_atom(value), do: Atom.to_string(value)
  defp label_value(value), do: to_string(value)

  defp record(%Counter{}, table, key, _value),
    do: :ets.update_counter(table, key, {2, 1}, {key, 0})

  defp record(%Sum{}, table, key, value) when is_number(value),
    do: :ets.update_counter(table, key, {2, to_micro(value)}, {key, 0})

  defp record(%LastValue{}, table, key, value) when is_number(value),
    do: :ets.insert(table, {key, value})

  defp record(%Distribution{} = metric, table, key, value) when is_number(value) do
    bucket_position = 4 + bucket_index(buckets(metric), value)
    default = List.to_tuple([key, 0, 0 | List.duplicate(0, length(buckets(metric)) + 1)])
    :ets.update_counter(table, key, [{2, 1}, {3, to_micro(value)}, {bucket_position, 1}], default)
  end

  defp record(_metric, _table, _key, _value), do: :ok

  defp bucket_index(bounds, value) do
    Enum.find_index(bounds, &(value <= &1)) || length(bounds)
  end

  defp buckets(%Distribution{reporter_options: options}),
    do: Keyword.get(options, :buckets, @default_buckets)

  defp to_micro(value), do: round(value * @micro)

  ## Rendering

  defp render_metric({index, metric}, table) do
    name = prometheus_name(metric)
    rows = rows_for(table, index)

    [
      help_line(name, metric),
      "# TYPE ",
      name,
      " ",
      prometheus_type(metric),
      "\n",
      render_samples(metric, name, Enum.sort(rows))
    ]
  end

  # Rows are 2-tuples for scalar metrics and wider tuples for histograms, so
  # select by key rather than by a fixed-arity match pattern. Scrapes are rare
  # (every 15s) and the table is small, so a full scan is acceptable.
  defp rows_for(table, index) do
    table
    |> :ets.tab2list()
    |> Enum.filter(&match?({^index, _labels}, elem(&1, 0)))
  end

  defp help_line(_name, %{description: nil}), do: []

  defp help_line(name, %{description: description}),
    do: ["# HELP ", name, " ", escape_help(description), "\n"]

  defp prometheus_type(%Counter{}), do: "counter"
  defp prometheus_type(%Sum{}), do: "counter"
  defp prometheus_type(%LastValue{}), do: "gauge"
  defp prometheus_type(%Distribution{}), do: "histogram"

  defp render_samples(%Counter{tags: []}, name, []), do: [name, " 0\n"]

  defp render_samples(%Distribution{} = metric, name, rows),
    do: Enum.map(rows, &render_histogram(metric, name, &1))

  defp render_samples(%Sum{}, name, rows),
    do: Enum.map(rows, fn {{_index, labels}, micro} -> sample(name, labels, micro / @micro) end)

  defp render_samples(_metric, name, rows),
    do: Enum.map(rows, fn {{_index, labels}, value} -> sample(name, labels, value) end)

  defp render_histogram(metric, name, row) do
    [{_index, labels}, count, sum_micro | bucket_counts] = Tuple.to_list(row)
    bounds = buckets(metric)

    {bucket_lines, _cumulative} =
      bounds
      |> Enum.zip(bucket_counts)
      |> Enum.map_reduce(0, fn {bound, bucket_count}, cumulative ->
        total = cumulative + bucket_count
        {sample(name <> "_bucket", labels ++ [{"le", format_number(bound)}], total), total}
      end)

    [
      bucket_lines,
      sample(name <> "_bucket", labels ++ [{"le", "+Inf"}], count),
      sample(name <> "_sum", labels, sum_micro / @micro),
      sample(name <> "_count", labels, count)
    ]
  end

  defp sample(name, [], value), do: [name, " ", format_number(value), "\n"]

  defp sample(name, labels, value) do
    rendered =
      labels
      |> Enum.map(fn {key, label} -> [key, "=\"", escape_label(label), "\""] end)
      |> Enum.intersperse(",")

    [name, "{", rendered, "} ", format_number(value), "\n"]
  end

  defp prometheus_name(%{reporter_options: options, name: name} = metric) do
    base = Keyword.get_lazy(options, :prometheus_name, fn -> Enum.join(name, "_") end)
    base = String.replace(base, ~r/[^a-zA-Z0-9_:]/, "_")

    case metric do
      %Counter{} -> if String.ends_with?(base, "_total"), do: base, else: base <> "_total"
      _other -> base
    end
  end

  defp format_number(value) when is_integer(value), do: Integer.to_string(value)

  defp format_number(value) when is_float(value) do
    if value == Float.round(value) and abs(value) < 1.0e15,
      do: value |> trunc() |> Integer.to_string(),
      else: :erlang.float_to_binary(value, [:short])
  end

  defp escape_label(value) do
    value
    |> String.replace("\\", "\\\\")
    |> String.replace("\"", "\\\"")
    |> String.replace("\n", "\\n")
  end

  defp escape_help(value) do
    value
    |> String.replace("\\", "\\\\")
    |> String.replace("\n", "\\n")
  end
end
