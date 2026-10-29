defmodule Palee.Analytics.Domain.ProgressStats do
  @moduledoc """
  Advanced progress statistics for a client's own training (ADR-098), built
  from completed executions: weekly volume, consistency, where sessions came
  from, and the score history of sections the client did more than once.
  Structured plan workouts (ADR-270) add their lifted volume (`volume_kg`,
  kg × reps, in the totals and per week) and `exercise_loads`: the heaviest
  set of each exercise per session, for exercises done in more than one
  session (`plan_workload` of `ListWorkoutExecutions`).
  `weeks` (default 12) is how many calendar weeks, this one included, the
  weekly chart, the consistency and `days` (sessions per day with training,
  for the calendar heatmap, ADR-194) cover.
  """

  @default_weeks 12

  def build(executions, %Date{} = today, weeks \\ @default_weeks)
      when is_integer(weeks) and weeks > 0 do
    completed =
      executions
      |> Enum.filter(&(value(&1, :status) == "completed" and value(&1, :completed_at_utc)))
      |> Enum.map(&Map.put(&1, :completed_on, DateTime.to_date(value(&1, :completed_at_utc))))

    weekly = weekly(completed, today, weeks)
    active_weeks = Enum.count(weekly, &(&1.sessions > 0))

    %{
      totals: %{
        sessions: length(completed),
        minutes: completed |> Enum.map(&minutes/1) |> Enum.sum(),
        workouts:
          completed |> Enum.map(&value(&1, :master_workout_id)) |> Enum.uniq() |> length(),
        volume_kg: completed |> Enum.map(&volume_kg/1) |> Enum.sum() |> round_kg()
      },
      weekly: weekly,
      days: days(completed, hd(weekly).week_start, today),
      consistency: %{
        weeks: weeks,
        active_weeks: active_weeks,
        percent: round(active_weeks * 100 / weeks),
        current_streak_weeks: streak(Enum.reverse(weekly))
      },
      sources: Enum.frequencies_by(completed, &to_string(value(&1, :source))),
      score_history: score_history(completed),
      exercise_loads: exercise_loads(completed)
    }
  end

  defp weekly(completed, today, weeks) do
    this_week = Date.beginning_of_week(today)
    by_week = Enum.group_by(completed, &Date.beginning_of_week(&1.completed_on))

    for offset <- (weeks - 1)..0//-1 do
      week_start = Date.add(this_week, -7 * offset)
      sessions = Map.get(by_week, week_start, [])

      %{
        week_start: week_start,
        sessions: length(sessions),
        minutes: sessions |> Enum.map(&minutes/1) |> Enum.sum(),
        volume_kg: sessions |> Enum.map(&volume_kg/1) |> Enum.sum() |> round_kg()
      }
    end
  end

  # Only days with a session, oldest first; the client fills the grid.
  defp days(completed, first_day, today) do
    completed
    |> Enum.map(& &1.completed_on)
    |> Enum.filter(&(Date.compare(&1, first_day) != :lt and Date.compare(&1, today) != :gt))
    |> Enum.frequencies()
    |> Enum.sort_by(&elem(&1, 0), Date)
    |> Enum.map(fn {date, sessions} -> %{date: date, sessions: sessions} end)
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

  # The heaviest set of each exercise per session, oldest first, for the
  # exercises lifted in more than one session.
  defp exercise_loads(completed) do
    completed
    |> Enum.flat_map(fn execution ->
      execution
      |> value(:plan_workload)
      |> top_sets()
      |> Enum.map(fn top ->
        %{
          key: exercise_key(top),
          name: value(top, :name),
          exercise_ref: value(top, :exercise_ref),
          execution_id: value(execution, :id),
          completed_on: execution.completed_on,
          load_kg: value(top, :load_kg),
          reps: value(top, :reps)
        }
      end)
    end)
    |> Enum.group_by(& &1.key)
    |> Enum.map(fn {_key, points} ->
      points = Enum.sort_by(points, & &1.completed_on, Date)
      latest = List.last(points)

      %{
        name: latest.name,
        exercise_ref: latest.exercise_ref,
        points: Enum.map(points, &Map.take(&1, [:execution_id, :completed_on, :load_kg, :reps]))
      }
    end)
    |> Enum.filter(&(length(&1.points) > 1))
    |> Enum.sort_by(&(&1.name || ""))
  end

  defp top_sets(%{} = workload), do: List.wrap(value(workload, :top_sets))
  defp top_sets(_workload), do: []

  defp exercise_key(top) do
    case value(top, :exercise_ref) do
      ref when is_binary(ref) -> {:ref, ref}
      _none -> {:name, top |> value(:name) |> to_string() |> String.trim() |> String.downcase()}
    end
  end

  defp volume_kg(execution) do
    case execution |> value(:plan_workload) |> value(:volume_kg) do
      kg when is_number(kg) -> kg
      _none -> 0
    end
  end

  defp round_kg(kg) when is_float(kg), do: Float.round(kg, 1)
  defp round_kg(kg), do: kg

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
