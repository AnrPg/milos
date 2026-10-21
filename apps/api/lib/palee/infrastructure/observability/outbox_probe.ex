defmodule Palee.Infrastructure.Observability.OutboxProbe do
  @moduledoc """
  Measures transactional-outbox lag. Post-commit effects (ADR-032/ADR-042) are
  durable Oban jobs, so outbox age is the age of the oldest job that is due
  (`scheduled_at <= now`) but not yet executed, per queue.

  Emits `[:palee, :outbox, :age]` with measurements `oldest_seconds`,
  `pending` (due `available`/`scheduled` jobs) and `retryable` (due jobs
  waiting for a retry), and metadata `%{queue: queue}`. Every configured
  queue is reported, with zeros when empty, so gauges recover after a backlog
  drains instead of freezing at their last non-zero value.
  """

  import Ecto.Query

  require Logger

  alias Palee.Repo

  @backlog_states ~w(available scheduled retryable)

  @doc "Emits one telemetry event per queue. Never raises (poller-safe)."
  def measure(options \\ []) do
    options
    |> snapshot()
    |> Enum.each(fn {queue, measurements} ->
      :telemetry.execute([:palee, :outbox, :age], measurements, %{queue: queue})
    end)
  rescue
    error ->
      Logger.warning("outbox_probe_failed reason=#{Exception.message(error)}")
      :ok
  end

  @doc "Returns `%{queue => %{oldest_seconds:, pending:, retryable:}}`."
  def snapshot(options \\ []) do
    now = Keyword.get_lazy(options, :now, &DateTime.utc_now/0)
    queues = Keyword.get_lazy(options, :queues, &configured_queues/0)
    empty = Map.new(queues, &{&1, empty_row()})

    now
    |> backlog_rows()
    |> Enum.reduce(empty, fn {queue, state, count, oldest}, acc ->
      row = Map.get(acc, queue, empty_row())
      Map.put(acc, queue, merge_row(row, now, state, count, oldest))
    end)
  end

  defp backlog_rows(now) do
    naive_now = DateTime.to_naive(now)

    Repo.all(
      from(job in Oban.Job,
        where: job.state in @backlog_states and job.scheduled_at <= ^naive_now,
        group_by: [job.queue, job.state],
        select: {job.queue, job.state, count(job.id), min(job.scheduled_at)}
      )
    )
  end

  defp empty_row, do: %{oldest_seconds: 0, pending: 0, retryable: 0}

  defp merge_row(row, now, state, count, oldest) do
    row = Map.put(row, :oldest_seconds, max(row.oldest_seconds, age_seconds(now, oldest)))

    case state do
      "retryable" -> Map.update!(row, :retryable, &(&1 + count))
      _due -> Map.update!(row, :pending, &(&1 + count))
    end
  end

  defp age_seconds(now, %DateTime{} = oldest), do: max(DateTime.diff(now, oldest, :second), 0)

  defp age_seconds(now, %NaiveDateTime{} = oldest),
    do: max(NaiveDateTime.diff(DateTime.to_naive(now), oldest, :second), 0)

  defp configured_queues do
    :palee
    |> Application.get_env(Oban, [])
    |> Keyword.get(:queues, [])
    |> Enum.map(fn {queue, _limit} -> to_string(queue) end)
  end
end
