defmodule MilosTraining.Analytics.Domain.ProgressStats do
  @moduledoc """
  Advanced progress statistics for a client's own training (ADR-098), built
  from completed executions: weekly volume, consistency, where sessions came
  from, and the score history of sections the client did more than once.
  """

  @weeks 12

  def build(executions, %Date{} = today) do
    completed =
      executions
      |> Enum.filter(&(value(&1, :status) == "completed" and value(&1, :completed_at_utc)))
      |> Enum.map(&Map.put(&1, :completed_on, DateTime.to_date(value(&1, :completed_at_utc))))

    weekly = weekly(completed, today)
    active_weeks = Enum.count(weekly, &(&1.sessions > 0))

    %{
      totals: %{
        sessions: length(completed),
        minutes: completed |> Enum.map(&minutes/1) |> Enum.sum(),
        workouts: completed |> Enum.map(&value(&1, :master_workout_id)) |> Enum.uniq() |> length()
      },
      weekly: weekly,
      consistency: %{
        weeks: @weeks,
        active_weeks: active_weeks,
        percent: round(active_weeks * 100 / @weeks),
        current_streak_weeks: streak(Enum.reverse(weekly))
      },
      sources: Enum.frequencies_by(completed, &to_string(value(&1, :source))),
      score_history: score_history(completed)
    }
  end

  defp weekly(completed, today) do
    this_week = Date.beginning_of_week(today)
    by_week = Enum.group_by(completed, &Date.beginning_of_week(&1.completed_on))

    for offset <- (@weeks - 1)..0//-1 do
      week_start = Date.add(this_week, -7 * offset)
      sessions = Map.get(by_week, week_start, [])

      %{
        week_start: week_start,
        sessions: length(sessions),
        minutes: sessions |> Enum.map(&minutes/1) |> Enum.sum()
      }
    end
  end

  # Consecutive weeks with training, counting back from this week; an empty
  # current week does not break a streak that ended last week.
  defp streak([%{sessions: 0} | earlier]), do: count_streak(earlier)
  defp streak(weeks), do: count_streak(weeks)

  defp count_streak(weeks), do: weeks |> Enum.take_while(&(&1.sessions > 0)) |> length()

  defp score_history(completed) do
    completed
    |> Enum.flat_map(&score_points/1)
    |> Enum.group_by(&{&1.workout_id, &1.section_key})
    |> Enum.filter(fn {_key, points} -> length(points) > 1 end)
    |> Enum.map(fn {{workout_id, _section_key}, points} ->
      points = Enum.sort_by(points, & &1.completed_on, Date)
      first = hd(points)

      %{
        workout_id: workout_id,
        workout_title: first.workout_title,
        section_id: first.section_id,
        section_name: first.section_name,
        unit: first.unit,
        points: Enum.map(points, &Map.take(&1, [:execution_id, :completed_on, :value]))
      }
    end)
    |> Enum.sort_by(&{&1.workout_title || "", &1.section_name || ""})
  end

  defp score_points(execution) do
    execution
    |> value(:section_scores)
    |> List.wrap()
    |> Enum.filter(&(value(&1, :value) != nil))
    |> Enum.map(fn score ->
      %{
        workout_id: value(execution, :master_workout_id),
        workout_title: value(execution, :workout_title),
        section_id: value(score, :section_id),
        # ADR-162: across providers, sections of one identity match by key.
        section_key: value(score, :section_key) || value(score, :section_id),
        section_name: value(score, :section_name),
        execution_id: value(execution, :id),
        completed_on: execution.completed_on,
        value: value(score, :value),
        unit: value(score, :unit)
      }
    end)
  end

  @timeline_limit 50

  @doc """
  The client's PR improvements over time, newest first, each with the score
  it replaced (`nil` for a first record). History rows hold the scores a PR
  had before it was beaten; the current score lives on the record itself.
  """
  def pr_timeline(history_entries, records \\ []) do
    current =
      Enum.map(records, fn record ->
        %{
          id: value(record, :id),
          pr_record_id: value(record, :id),
          name: value(record, :name),
          unit: value(record, :unit),
          higher_is_better: value(record, :higher_is_better),
          beaten_on: value(record, :beaten_on),
          score: value(record, :current_score),
          inserted_at: value(record, :updated_at)
        }
      end)

    (history_entries ++ current)
    |> Enum.group_by(&value(&1, :pr_record_id))
    |> Enum.flat_map(fn {_record_id, entries} ->
      entries
      |> Enum.sort_by(&{to_string(value(&1, :beaten_on)), to_string(value(&1, :inserted_at))})
      |> Enum.map_reduce(nil, fn entry, previous ->
        score = value(entry, :score)

        {%{
           id: value(entry, :id),
           pr_record_id: value(entry, :pr_record_id),
           name: value(entry, :name),
           unit: value(entry, :unit),
           higher_is_better: value(entry, :higher_is_better),
           beaten_on: value(entry, :beaten_on),
           score: score,
           previous_score: previous,
           change: previous && score - previous
         }, score}
      end)
      |> elem(0)
    end)
    |> Enum.sort_by(&{to_string(&1.beaten_on), &1.name || ""}, :desc)
    |> Enum.take(@timeline_limit)
  end

  defp minutes(execution), do: div(value(execution, :total_elapsed_ms) || 0, 60_000)

  defp value(map, key) when is_map(map), do: Map.get(map, key, Map.get(map, to_string(key)))
  defp value(_map, _key), do: nil
end
