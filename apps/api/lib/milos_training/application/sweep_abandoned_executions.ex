defmodule MilosTraining.Application.SweepAbandonedExecutions do
  @moduledoc """
  Records `workout_execution_abandoned` for one tenant's executions that were
  started but not completed within the abandonment threshold (ADR-123).

  * Threshold: `config :milos_training, :execution_abandonment_hours`
    (default #{6}h). An execution started at least that long ago and still not
    completed is abandoned.
  * Window: only executions started in the #{48}h before the threshold are
    scanned, so an hourly sweep sees each candidate many times (any one run
    may fail) without rescanning history forever.
  * Idempotent: the event dedupes on the execution id, and ids that already
    have an event are filtered out before any work is done, so re-running the
    sweep never records a second event for the same execution.
  * Abandon point: the execution's last persisted snapshot gives the segment
    index; the format comes from the workout's timer sequence at that index.

  Returns `{:ok, recorded_count}`.
  """

  alias MilosTraining.Application.TrackAnalyticsEvent
  alias MilosTraining.{Analytics, Execution, Workouts}

  @default_threshold_hours 6
  @window_hours 48
  @batch_limit 500
  @event "workout_execution_abandoned"

  def call(organization_id, now \\ DateTime.utc_now(), opts \\ [])

  def call(organization_id, %DateTime{} = now, opts) when is_binary(organization_id) do
    threshold = Keyword.get(opts, :threshold_hours, threshold_hours())
    started_before = DateTime.add(now, -threshold * 3_600, :second)
    started_after = DateTime.add(started_before, -@window_hours * 3_600, :second)
    tenant = %{organization_id: organization_id}

    candidates =
      tenant
      |> Execution.with_execution_context(fn ->
        Execution.list_stale_executions(started_before, started_after, @batch_limit)
      end)
      |> List.wrap()
      |> Enum.filter(&Execution.execution_abandoned?(&1, now, threshold))

    recorded = already_recorded(tenant, candidates)

    count =
      candidates
      |> Enum.reject(&MapSet.member?(recorded, &1.id))
      |> Enum.reduce({0, %{}}, fn execution, {count, segment_cache} ->
        {segments, segment_cache} = segments_for(execution, segment_cache)
        record(execution, segments, now, threshold)
        {count + 1, segment_cache}
      end)
      |> elem(0)

    {:ok, count}
  end

  def call(_organization_id, _now, _opts), do: {:error, :organization_context_required}

  defp already_recorded(_tenant, []), do: MapSet.new()

  defp already_recorded(tenant, candidates) do
    tenant
    |> Analytics.with_tenant_context(fn ->
      Analytics.list_recorded_dedupe_keys(@event, Enum.map(candidates, & &1.id))
    end)
    |> List.wrap()
    |> MapSet.new()
  end

  defp record(execution, segments, now, threshold) do
    last_progress_at =
      Execution.with_execution_context(
        %{organization_id: execution.organization_id, user_id: execution.user_id},
        fn -> Execution.last_progress_at(execution.id) end
      )

    facts =
      execution
      |> Map.put(:last_progress_at, normalize_datetime(last_progress_at))
      |> Execution.abandonment_analytics_facts(segments, now)
      |> Map.put(:threshold_hours, threshold)

    TrackAnalyticsEvent.call(@event, nil, execution, %{
      user_id: execution.user_id,
      occurred_at: now,
      metadata: facts
    })
  end

  defp segments_for(%{master_workout_id: nil}, cache), do: {[], cache}

  defp segments_for(execution, cache) do
    key = {execution.master_workout_id, execution.scale_level_slug}

    case Map.fetch(cache, key) do
      {:ok, segments} ->
        {segments, cache}

      :error ->
        segments =
          Workouts.with_tenant_context(%{organization_id: execution.organization_id}, fn ->
            case resolve_workout(execution.master_workout_id, execution.scale_level_slug) do
              nil -> []
              workout -> Execution.build_timer_sequence(workout)
            end
          end)

        segments = if is_list(segments), do: segments, else: []
        {segments, Map.put(cache, key, segments)}
    end
  end

  defp resolve_workout(workout_id, slug) when slug in [nil, ""],
    do: Workouts.get_workout(workout_id)

  defp resolve_workout(workout_id, slug),
    do: Workouts.materialize_workout_for_scale(workout_id, slug)

  defp normalize_datetime(%DateTime{} = at), do: at
  defp normalize_datetime(_other), do: nil

  defp threshold_hours do
    case Application.get_env(:milos_training, :execution_abandonment_hours) do
      hours when is_integer(hours) and hours > 0 -> hours
      _unset -> @default_threshold_hours
    end
  end
end
