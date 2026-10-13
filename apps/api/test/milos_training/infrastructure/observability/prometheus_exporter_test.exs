defmodule MilosTraining.Infrastructure.Observability.PrometheusExporterTest do
  use ExUnit.Case, async: true

  import Telemetry.Metrics

  alias MilosTraining.Infrastructure.Observability.PrometheusExporter

  setup do
    id = System.unique_integer([:positive])
    prefix = [:prometheus_exporter_test, String.to_atom("case#{id}")]
    name = Module.concat(__MODULE__, "Exporter#{id}")
    {:ok, prefix: prefix, name: name}
  end

  defp start_exporter(name, metrics) do
    start_supervised!({PrometheusExporter, name: name, metrics: metrics})
    name
  end

  defp scrape(name), do: name |> PrometheusExporter.scrape() |> IO.iodata_to_binary()

  test "counts events per label set and renders HELP/TYPE lines", %{prefix: prefix, name: name} do
    start_exporter(name, [
      counter(prefix ++ [:rejected, :count],
        tags: [:reason],
        description: "Rejected uploads",
        reporter_options: [prometheus_name: "milos_test_rejected_total"]
      )
    ])

    :telemetry.execute(prefix ++ [:rejected], %{count: 1}, %{reason: :too_large, other: "x"})
    :telemetry.execute(prefix ++ [:rejected], %{count: 1}, %{reason: :too_large})
    :telemetry.execute(prefix ++ [:rejected], %{count: 1}, %{reason: "bad_type"})

    output = scrape(name)

    assert output =~ "# HELP milos_test_rejected_total Rejected uploads\n"
    assert output =~ "# TYPE milos_test_rejected_total counter\n"
    assert output =~ ~s(milos_test_rejected_total{reason="too_large"} 2\n)
    assert output =~ ~s(milos_test_rejected_total{reason="bad_type"} 1\n)
  end

  test "renders untagged counters as zero before the first event", %{prefix: prefix, name: name} do
    start_exporter(name, [counter(prefix ++ [:failure, :count])])

    output = scrape(name)

    expected_name = Enum.join(prefix ++ [:failure, :count], "_") <> "_total"
    assert output =~ "#{expected_name} 0\n"
  end

  test "tracks sums and last values", %{prefix: prefix, name: name} do
    start_exporter(name, [
      sum(prefix ++ [:bytes, :size], reporter_options: [prometheus_name: "milos_test_bytes"]),
      last_value(prefix ++ [:outbox, :oldest_seconds],
        tags: [:queue],
        reporter_options: [prometheus_name: "milos_test_outbox_oldest_seconds"]
      )
    ])

    :telemetry.execute(prefix ++ [:bytes], %{size: 1.5}, %{})
    :telemetry.execute(prefix ++ [:bytes], %{size: 2}, %{})
    :telemetry.execute(prefix ++ [:outbox], %{oldest_seconds: 40}, %{queue: :default})
    :telemetry.execute(prefix ++ [:outbox], %{oldest_seconds: 12.5}, %{queue: :default})

    output = scrape(name)

    assert output =~ "# TYPE milos_test_bytes counter\n"
    assert output =~ "milos_test_bytes 3.5\n"
    assert output =~ "# TYPE milos_test_outbox_oldest_seconds gauge\n"
    assert output =~ ~s(milos_test_outbox_oldest_seconds{queue="default"} 12.5\n)
  end

  test "renders distributions as cumulative Prometheus histograms", %{prefix: prefix, name: name} do
    start_exporter(name, [
      distribution(prefix ++ [:request, :duration],
        tags: [:route],
        reporter_options: [prometheus_name: "milos_test_duration_seconds", buckets: [0.1, 0.5, 1]]
      )
    ])

    for value <- [0.05, 0.1, 0.3, 2.0] do
      :telemetry.execute(prefix ++ [:request], %{duration: value}, %{route: "/api/x"})
    end

    output = scrape(name)

    assert output =~ "# TYPE milos_test_duration_seconds histogram\n"
    assert output =~ ~s(milos_test_duration_seconds_bucket{route="/api/x",le="0.1"} 2\n)
    assert output =~ ~s(milos_test_duration_seconds_bucket{route="/api/x",le="0.5"} 3\n)
    assert output =~ ~s(milos_test_duration_seconds_bucket{route="/api/x",le="1"} 3\n)
    assert output =~ ~s(milos_test_duration_seconds_bucket{route="/api/x",le="+Inf"} 4\n)
    assert output =~ ~s(milos_test_duration_seconds_sum{route="/api/x"} 2.45\n)
    assert output =~ ~s(milos_test_duration_seconds_count{route="/api/x"} 4\n)
  end

  test "escapes label values and honours keep predicates", %{prefix: prefix, name: name} do
    start_exporter(name, [
      counter(prefix ++ [:event, :count],
        tags: [:reason],
        keep: &(&1[:reason] != "ignored"),
        reporter_options: [prometheus_name: "milos_test_events_total"]
      )
    ])

    :telemetry.execute(prefix ++ [:event], %{count: 1}, %{reason: ~s(quote"back\\slash\nline)})
    :telemetry.execute(prefix ++ [:event], %{count: 1}, %{reason: "ignored"})

    output = scrape(name)

    assert output =~ ~s(milos_test_events_total{reason="quote\\"back\\\\slash\\nline"} 1\n)
    refute output =~ "ignored"
  end

  test "keeps recording after a metric definition raises on unexpected metadata", %{
    prefix: prefix,
    name: name
  } do
    start_exporter(name, [
      counter(prefix ++ [:job, :count],
        tags: [:queue],
        tag_values: fn %{job: job} -> %{queue: job.queue} end,
        reporter_options: [prometheus_name: "milos_test_jobs_total"]
      )
    ])

    :telemetry.execute(prefix ++ [:job], %{count: 1}, %{unexpected: true})
    :telemetry.execute(prefix ++ [:job], %{count: 1}, %{job: %{queue: "default"}})

    assert scrape(name) =~ ~s(milos_test_jobs_total{queue="default"} 1\n)
  end

  test "reattaches handlers after a restart", %{prefix: prefix, name: name} do
    start_exporter(name, [
      counter(prefix ++ [:restart, :count],
        reporter_options: [prometheus_name: "milos_test_restart_total"]
      )
    ])

    name |> Process.whereis() |> Process.exit(:kill)
    Process.sleep(20)
    :telemetry.execute(prefix ++ [:restart], %{count: 1}, %{})

    assert scrape(name) =~ "milos_test_restart_total 1\n"
  end
end
