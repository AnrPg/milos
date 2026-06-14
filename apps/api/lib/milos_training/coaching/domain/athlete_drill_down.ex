defmodule MilosTraining.Coaching.Domain.AthleteDrillDown do
  @moduledoc false

  @active_window_days 14
  @recent_window_days 30

  def build(athlete, assignments, executions, notes, today \\ Date.utc_today()) do
    assignments = Enum.map(assignments || [], &normalize_assignment(&1, today))
    executions = Enum.map(executions || [], &normalize_execution/1)
    notes = Enum.map(notes || [], &normalize_admin_note/1)

    %{
      identity: identity(athlete),
      recent_activity: recent_activity(executions, assignments, today),
      assigned_workouts: assignments,
      execution_history: execution_history(executions),
      score_trends: score_trends(executions),
      notes_context: notes_context(notes, executions),
      attention_cues: attention_cues(assignments, executions, notes, today),
      actions: actions(athlete)
    }
  end

  defp identity(athlete) do
    %{
      user_id: field(athlete, :id),
      nickname: field(athlete, :nickname),
      role: role_string(field(athlete, :role))
    }
  end

  defp recent_activity(executions, assignments, today) do
    completed = Enum.filter(executions, &(field(&1, :status) == "completed"))
    last_completed_at = completed |> Enum.map(&field(&1, :completed_at_utc)) |> latest_datetime()
    last_started_at = executions |> Enum.map(&field(&1, :started_at_utc)) |> latest_datetime()
    state = activity_state(last_completed_at, assignments, today)

    %{
      state: state,
      reason: activity_reason(state, last_completed_at, assignments, today),
      urgency: activity_urgency(state, assignments, today),
      completed_workouts_last_14_days:
        count_completed_since(completed, today, @active_window_days),
      completed_workouts_last_30_days:
        count_completed_since(completed, today, @recent_window_days),
      last_completed_at: last_completed_at,
      last_started_at: last_started_at
    }
  end

  defp normalize_assignment(assignment, today) do
    workout = field(assignment, :workout) || %{}
    scheduled_for = normalize_date(field(assignment, :scheduled_for))

    %{
      id: field(assignment, :id),
      master_workout_id: field(assignment, :master_workout_id) || field(workout, :id),
      scheduled_for: scheduled_for,
      status: assignment_status(assignment, scheduled_for, today),
      admin_notes: field(assignment, :admin_notes),
      workout: %{
        id: field(workout, :id),
        title: field(workout, :title),
        type: string_value(field(workout, :type))
      },
      execution_scores: field(assignment, :execution_scores) || []
    }
  end

  defp assignment_status(assignment, scheduled_for, today) do
    cond do
      field(assignment, :my_athlete_status) == "rejected" -> "rejected"
      field(assignment, :execution_status) == "completed" -> "completed"
      overdue_date?(scheduled_for, today) -> "overdue"
      true -> "upcoming"
    end
  end

  defp normalize_execution(execution) do
    %{
      id: field(execution, :id),
      master_workout_id: field(execution, :master_workout_id),
      workout_title: field(execution, :workout_title),
      workout_type: string_value(field(execution, :workout_type)),
      source: string_value(field(execution, :source)),
      status: string_value(field(execution, :status)),
      started_at_utc: normalize_datetime(field(execution, :started_at_utc)),
      completed_at_utc: normalize_datetime(field(execution, :completed_at_utc)),
      section_scores: normalize_section_scores(field(execution, :section_scores) || []),
      exercise_notes: normalize_exercise_notes(field(execution, :exercise_notes) || [])
    }
  end

  defp execution_history(executions) do
    executions
    |> Enum.sort_by(&execution_sort_datetime/1, {:desc, DateTime})
    |> Enum.map(fn execution ->
      %{
        id: execution.id,
        master_workout_id: execution.master_workout_id,
        workout_title: execution.workout_title,
        workout_type: execution.workout_type,
        source: execution.source,
        status: execution.status,
        started_at_utc: execution.started_at_utc,
        completed_at_utc: execution.completed_at_utc,
        section_scores: execution.section_scores,
        exercise_note_count: length(execution.exercise_notes)
      }
    end)
  end

  defp score_trends(executions) do
    executions
    |> Enum.flat_map(fn execution ->
      Enum.map(execution.section_scores, fn score ->
        %{
          execution_id: execution.id,
          workout_type: execution.workout_type,
          workout_title: execution.workout_title,
          completed_at: execution.completed_at_utc,
          section_id: field(score, :section_id),
          section_name: field(score, :section_name),
          value: field(score, :value),
          unit: field(score, :unit)
        }
      end)
    end)
    |> Enum.reject(&(is_nil(&1.workout_type) or is_nil(&1.value)))
    |> Enum.group_by(& &1.workout_type)
    |> Enum.map(fn {workout_type, entries} ->
      %{
        workout_type: workout_type,
        entries: Enum.sort_by(entries, &score_sort_datetime/1, DateTime)
      }
    end)
    |> Enum.sort_by(& &1.workout_type)
  end

  defp notes_context(notes, executions) do
    notes
    |> Kernel.++(execution_note_context(executions))
    |> Enum.sort_by(&note_sort_datetime/1, {:desc, DateTime})
  end

  defp normalize_admin_note(message) do
    %{
      type: "admin_note",
      id: field(message, :id),
      admin_id: field(message, :sender_id),
      body: field(message, :body),
      inserted_at: normalize_datetime(field(message, :inserted_at))
    }
  end

  defp execution_note_context(executions) do
    Enum.flat_map(executions, fn execution ->
      Enum.map(execution.exercise_notes, fn note ->
        %{
          type: "athlete_execution_note",
          id: field(note, :id),
          execution_id: execution.id,
          workout_title: execution.workout_title,
          body: field(note, :note_text) || field(note, :body),
          selected_text: field(note, :selected_text),
          tags: field(note, :tags) || [],
          inserted_at: normalize_datetime(field(note, :inserted_at))
        }
      end)
    end)
  end

  defp attention_cues(assignments, executions, notes, today) do
    []
    |> Kernel.++(overdue_assignment_cues(assignments, today))
    |> maybe_add_inactive_cue(executions, today)
    |> maybe_add_no_notes_cue(notes, executions)
    |> Enum.sort_by(&cue_sort/1)
  end

  defp overdue_assignment_cues(assignments, today) do
    assignments
    |> Enum.filter(&(&1.status == "overdue" and overdue_date?(&1.scheduled_for, today)))
    |> Enum.map(fn assignment ->
      %{
        type: "overdue_assignment",
        severity: "high",
        reason: "assignment_not_completed",
        title: "Overdue assigned workout",
        assignment_id: assignment.id,
        scheduled_for: assignment.scheduled_for
      }
    end)
  end

  defp maybe_add_inactive_cue(cues, executions, today) do
    last_completed_at =
      executions
      |> Enum.map(&field(&1, :completed_at_utc))
      |> latest_datetime()

    if is_nil(last_completed_at) or days_between(last_completed_at, today) > @recent_window_days do
      [
        %{
          type: "no_recent_completion",
          severity: "medium",
          reason: "no_completed_workout_in_30_days",
          title: "No recent completed workout",
          last_completed_at: last_completed_at
        }
        | cues
      ]
    else
      cues
    end
  end

  defp maybe_add_no_notes_cue(cues, [], []), do: cues

  defp maybe_add_no_notes_cue(cues, notes, _executions) do
    if notes == [] do
      [
        %{
          type: "no_admin_note",
          severity: "low",
          reason: "no_admin_note_recorded",
          title: "No coach note recorded"
        }
        | cues
      ]
    else
      cues
    end
  end

  defp actions(athlete) do
    write_available? = role_string(field(athlete, :role)) == "athlete"

    [
      action("write_note", write_available?, "athlete_role_required"),
      action("review_history", true),
      action("assign_workout", write_available?, "athlete_role_required")
    ]
  end

  defp action(key, true), do: %{key: key, available: true, reason: nil}
  defp action(key, false, reason), do: %{key: key, available: false, reason: reason}

  defp action(key, available, reason),
    do: if(available, do: action(key, true), else: action(key, false, reason))

  defp normalize_section_scores(section_scores) do
    Enum.map(section_scores, fn score ->
      %{
        section_id: field(score, :section_id),
        section_name: field(score, :section_name),
        value: field(score, :value),
        unit: field(score, :unit)
      }
    end)
  end

  defp normalize_exercise_notes(notes) when is_list(notes), do: notes
  defp normalize_exercise_notes(_notes), do: []

  defp activity_state(last_completed_at, assignments, today) do
    cond do
      is_nil(last_completed_at) and Enum.any?(assignments, &(&1.status == "upcoming")) ->
        "drifting"

      is_nil(last_completed_at) ->
        "inactive"

      days_between(last_completed_at, today) <= @active_window_days ->
        "active"

      days_between(last_completed_at, today) <= @recent_window_days ->
        "drifting"

      Enum.any?(assignments, &(&1.status == "upcoming")) ->
        "drifting"

      true ->
        "inactive"
    end
  end

  defp activity_reason("active", _last_completed_at, _assignments, _today),
    do: "recent_completion"

  defp activity_reason("drifting", nil, assignments, _today) do
    if Enum.any?(assignments, &(&1.status == "upcoming")) do
      "assigned_without_completion"
    else
      "completion_inside_30_days"
    end
  end

  defp activity_reason("drifting", _last_completed_at, _assignments, _today),
    do: "completion_inside_30_days"

  defp activity_reason("inactive", nil, _assignments, _today), do: "no_completed_workout"

  defp activity_reason("inactive", _last_completed_at, _assignments, _today),
    do: "no_recent_completion"

  defp activity_reason(state, _last_completed_at, _assignments, _today), do: state

  defp activity_urgency(state, assignments, today) do
    cond do
      Enum.any?(assignments, &(&1.status == "overdue" and overdue_date?(&1.scheduled_for, today))) ->
        "urgent"

      Enum.any?(assignments, &(&1.status == "overdue")) ->
        "urgent"

      state == "active" ->
        "normal"

      true ->
        "attention"
    end
  end

  defp count_completed_since(executions, today, days) do
    Enum.count(executions, fn execution ->
      case field(execution, :completed_at_utc) do
        nil -> false
        completed_at -> days_between(completed_at, today) <= days
      end
    end)
  end

  defp latest_datetime(values) do
    values
    |> Enum.map(&normalize_datetime/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.sort({:desc, DateTime})
    |> List.first()
  end

  defp execution_sort_datetime(execution),
    do: execution.completed_at_utc || execution.started_at_utc || DateTime.from_unix!(0)

  defp score_sort_datetime(%{completed_at: %DateTime{} = completed_at}), do: completed_at
  defp score_sort_datetime(_score), do: DateTime.from_unix!(0)

  defp note_sort_datetime(%{inserted_at: %DateTime{} = inserted_at}), do: inserted_at
  defp note_sort_datetime(_note), do: DateTime.from_unix!(0)

  defp cue_sort(cue), do: {severity_sort(field(cue, :severity)), field(cue, :type) || ""}
  defp severity_sort("high"), do: 0
  defp severity_sort("medium"), do: 1
  defp severity_sort(_severity), do: 2

  defp overdue_date?(nil, _today), do: false
  defp overdue_date?(%Date{} = date, today), do: Date.compare(date, today) == :lt

  defp days_between(%DateTime{} = date_time, today),
    do: Date.diff(today, DateTime.to_date(date_time))

  defp days_between(_value, _today), do: @recent_window_days + 1

  defp normalize_date(%Date{} = date), do: date

  defp normalize_date(value) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> date
      {:error, _reason} -> nil
    end
  end

  defp normalize_date(_value), do: nil

  defp normalize_datetime(%DateTime{} = date_time), do: date_time

  defp normalize_datetime(%NaiveDateTime{} = date_time),
    do: DateTime.from_naive!(date_time, "Etc/UTC")

  defp normalize_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, date_time, _offset} -> date_time
      {:error, _reason} -> nil
    end
  end

  defp normalize_datetime(_value), do: nil

  defp field(nil, _key), do: nil
  defp field(map, key) when is_map(map), do: Map.get(map, key) || Map.get(map, to_string(key))
  defp field(struct, key), do: Map.get(struct, key)

  defp role_string(nil), do: nil
  defp role_string(role), do: to_string(role)

  defp string_value(nil), do: nil
  defp string_value(value), do: to_string(value)
end
