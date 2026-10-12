defmodule MilosTraining.Infrastructure.Observability.OutboxProbeTest do
  use MilosTraining.DataCase, async: true

  alias MilosTraining.Infrastructure.Observability.OutboxProbe
  alias MilosTraining.TestSupport.TelemetryCapture

  @now ~U[2026-10-12 12:00:00.000000Z]

  defp insert_job!(queue, state, scheduled_at) do
    %{}
    |> Oban.Job.new(worker: "MilosTraining.Workers.OutboxProbeTestWorker", queue: queue)
    |> Ecto.Changeset.put_change(:state, state)
    |> Ecto.Changeset.put_change(:scheduled_at, scheduled_at)
    |> Repo.insert!()
  end

  test "reports the oldest due job age and backlog per configured queue" do
    insert_job!("notifications", "available", DateTime.add(@now, -90, :second))
    insert_job!("notifications", "available", DateTime.add(@now, -5, :second))
    insert_job!("notifications", "retryable", DateTime.add(@now, -30, :second))
    # Not yet due: scheduled in the future, so it is not outbox lag.
    insert_job!("notifications", "scheduled", DateTime.add(@now, 600, :second))
    # Terminal states never count as backlog.
    insert_job!("default", "completed", DateTime.add(@now, -3_600, :second))
    insert_job!("default", "discarded", DateTime.add(@now, -3_600, :second))

    snapshot = OutboxProbe.snapshot(now: @now, queues: ["default", "notifications"])

    assert snapshot["notifications"] == %{oldest_seconds: 90, pending: 2, retryable: 1}
    assert snapshot["default"] == %{oldest_seconds: 0, pending: 0, retryable: 0}
  end

  test "includes queues that only exist in the jobs table" do
    insert_job!("legacy", "available", DateTime.add(@now, -12, :second))

    snapshot = OutboxProbe.snapshot(now: @now, queues: [])

    assert snapshot["legacy"] == %{oldest_seconds: 12, pending: 1, retryable: 0}
  end

  test "emits one outbox age telemetry event per queue" do
    insert_job!("analytics", "available", DateTime.add(@now, -42, :second))
    TelemetryCapture.capture([[:milos, :outbox, :age]])

    assert :ok = OutboxProbe.measure(now: @now, queues: ["analytics", "default"])

    assert_received {:telemetry_event, [:milos, :outbox, :age],
                     %{oldest_seconds: 42, pending: 1, retryable: 0}, %{queue: "analytics"}}

    assert_received {:telemetry_event, [:milos, :outbox, :age],
                     %{oldest_seconds: 0, pending: 0, retryable: 0}, %{queue: "default"}}
  end
end
