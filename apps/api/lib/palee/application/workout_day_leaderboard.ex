defmodule Palee.Application.WorkoutDayLeaderboard do
  @moduledoc """
  The ranking of one WOD's results over a window of the gym's day (ADR-138
  D6), shared by the `#wod-σήμερα` card and the box screen (ADR-253).

  Results are the in-app executions and logged scores of the window, read in
  the gym's scope. A result kept `private` in its owner's journal never
  ranks. Only members who opted in to leaderboards (`leaderboard_opt_ins`)
  rank, plus `include_user_id` (the card shows the viewer their own place);
  `exclude_user_ids` are left out before ranking. The ranking follows the
  WOD's scored section.
  """

  alias Palee.{Execution, Gamification}

  @default_limit 20

  @doc """
  `%{section, rows}`: the scored section (nil when the WOD has none) and up to
  `limit` rows `%{rank, user_id, scale_level_slug, value, unit, opted_in}`.
  Options: `include_user_id`, `exclude_user_ids`, `limit`, `results` (already
  read results of the window, to avoid reading them twice).
  """
  def rank(context, workout, %DateTime{} = from, %DateTime{} = to, opts \\ []) do
    section = ranked_section(workout)
    viewer_id = opts[:include_user_id]
    excluded = MapSet.new(opts[:exclude_user_ids] || [])

    results =
      (opts[:results] || results(context, workout && workout.id, from, to))
      |> Enum.reject(&(&1.journal_visibility == "private"))
      |> Enum.reject(&MapSet.member?(excluded, &1.user_id))

    opted_in = opted_in(context, results)

    rows =
      results
      |> Enum.filter(&(MapSet.member?(opted_in, &1.user_id) or &1.user_id == viewer_id))
      |> Execution.rank_workout_results(section)
      |> Enum.reject(&is_nil(&1.rank))
      |> Enum.take(opts[:limit] || @default_limit)
      |> Enum.map(fn row ->
        %{
          rank: row.rank,
          user_id: row.user_id,
          scale_level_slug: row.scale_level_slug,
          value: row.score && to_string(row.score["value"] || row.score[:value]),
          unit: row.score && (row.score["unit"] || row.score[:unit]),
          opted_in: MapSet.member?(opted_in, row.user_id)
        }
      end)

    %{section: section, rows: rows}
  end

  @doc "Every finished result of the WOD in the window (executions and log entries)."
  def results(_context, nil, _from, _to), do: []

  def results(context, workout_id, from, to),
    do: Execution.list_workout_results(context, workout_id, from, to)

  @doc """
  The WOD's scored section; for a workout written in text sections
  (ADR-180), the first score its coach set.
  """
  def ranked_section(nil), do: nil

  def ranked_section(workout) do
    case Execution.training_log_scoreable_sections(workout) do
      [section | _rest] -> section
      [] -> workout |> Execution.text_section_metrics() |> List.first()
    end
  end

  defp opted_in(context, results) do
    Gamification.with_tenant_context(context, fn ->
      results
      |> Enum.map(& &1.user_id)
      |> Enum.uniq()
      |> Gamification.leaderboard_opted_in_user_ids()
    end)
    |> MapSet.new()
  end
end
