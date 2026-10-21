defmodule MilosTraining.Application.AthleteTrainingVolume do
  @moduledoc """
  What the athlete actually trained in a window, exercise by exercise, across
  every provider (ADR-164; account-level like ADR-162). Shared by the anatomy
  atlas and the Πρόοδος coverage sections (P3-M3).

  Read in the member's personal session (row security admits their own rows
  in every organization):

    * completed executions: the exercises of the workout done (at its scale
      level when one was chosen), each with the coach's set count, else 1;
    * logged training-log entries (voided ones never): their performed
      exercises with the sets written, else 1; an entry without performed
      exercises falls back to the exercises of its workout;
    * the felt feedback written on those same entries.

  Every exercise is resolved to its Quick Text catalog id (`exercise_ref`,
  nil when not recognised). A workout is read once per window, in its own
  organization's context (like `ListWorkoutExecutions`); one that cannot be
  read any more contributes nothing.
  """

  alias MilosTraining.{Execution, Journal, Organizations, Workouts}

  @log_limit 2_000

  @type performance :: %{
          kind: String.t(),
          id: Ecto.UUID.t(),
          organization_id: Ecto.UUID.t() | nil,
          at: DateTime.t(),
          exercises: [
            %{exercise_ref: String.t() | nil, name: String.t() | nil, sets: pos_integer()}
          ]
        }

  @doc """
  `%{performances: [performance], felt: [%{entry_kind, entry_id, felt_muscles,
  felt_qualities}]}` for everything done at or after `since` (a `DateTime`).
  """
  def load(%{user_id: user_id} = context, %DateTime{} = since) do
    {executions, logs, felt} =
      Execution.with_execution_context(context, fn ->
        executions =
          user_id
          |> Execution.list_executions_for_user()
          |> Enum.filter(&completed_since?(&1, since))

        logs =
          user_id
          |> Execution.list_training_log_items(:none, @log_limit, :owner)
          |> Enum.filter(&logged_since?(&1, since))

        felt =
          feedback("execution", executions, user_id) ++
            feedback("training_log", logs, user_id)

        {executions, logs, felt}
      end)

    workouts = workouts(executions ++ Enum.filter(logs, &needs_workout?/1))

    %{
      performances:
        Enum.map(executions, &execution(&1, workouts)) ++ Enum.map(logs, &log(&1, workouts)),
      felt: felt
    }
  end

  defp completed_since?(execution, since) do
    to_string(execution.status) == "completed" and match?(%DateTime{}, execution.completed_at_utc) and
      DateTime.compare(execution.completed_at_utc, since) != :lt
  end

  defp logged_since?(entry, since) do
    Map.get(entry, :status, "logged") == "logged" and match?(%DateTime{}, entry.performed_at_utc) and
      DateTime.compare(entry.performed_at_utc, since) != :lt
  end

  defp feedback(_kind, [], _user_id), do: []

  defp feedback(kind, entries, user_id) do
    kind
    |> Journal.goal_feedback_by_entry(Enum.map(entries, & &1.id), user_id)
    |> Map.values()
    |> Enum.map(
      &%{
        entry_kind: kind,
        entry_id: &1.entry_id,
        felt_muscles: &1.felt_muscles || [],
        felt_qualities: &1.felt_qualities || []
      }
    )
  end

  defp execution(execution, workouts) do
    %{
      kind: "execution",
      id: execution.id,
      organization_id: execution.organization_id,
      at: execution.completed_at_utc,
      exercises: workout_exercises(execution, workouts)
    }
  end

  defp log(entry, workouts) do
    exercises =
      case performed(entry.performed_exercises) do
        [] -> workout_exercises(entry, workouts)
        performed -> performed
      end

    %{
      kind: "training_log",
      id: entry.id,
      organization_id: entry.organization_id,
      at: entry.performed_at_utc,
      exercises: exercises
    }
  end

  defp needs_workout?(entry), do: performed(entry.performed_exercises) == []

  defp performed(rows) do
    for row <- List.wrap(rows), is_map(row), name = field(row, :name), is_binary(name) do
      entry = Workouts.resolve_catalog_exercise(field(row, :exercise_ref), name)
      %{exercise_ref: entry && entry.id, name: name, sets: sets(field(row, :sets))}
    end
  end

  defp workout_exercises(
         %{organization_id: org_id, master_workout_id: workout_id} = item,
         workouts
       )
       when is_binary(org_id) and is_binary(workout_id) do
    case Map.get(workouts, {org_id, workout_id}) do
      nil ->
        []

      workout ->
        workout
        |> scaled(Map.get(item, :scale_level_slug))
        |> Workouts.goal_exercises()
        |> Enum.map(&%{exercise_ref: &1.exercise_ref, name: &1.name, sets: sets(&1.weight)})
    end
  end

  defp workout_exercises(_item, _workouts), do: []

  # Scale levels live on structured sections; a free-text workout has none.
  defp scaled(%{sections: [_ | _]} = workout, slug) when is_binary(slug) and slug != "",
    do: Workouts.materialize_for_scale(workout, slug)

  defp scaled(workout, _slug), do: workout

  defp workouts(items) do
    items
    |> Enum.filter(
      &(is_binary(&1.organization_id) and is_binary(Map.get(&1, :master_workout_id)))
    )
    |> Enum.map(&{&1.organization_id, &1.master_workout_id})
    |> Enum.uniq()
    |> Enum.reduce(%{}, fn {org_id, workout_id} = key, acc ->
      case fetch_workout(org_id, workout_id) do
        nil -> acc
        workout -> Map.put(acc, key, workout)
      end
    end)
  end

  # The workout belongs to the gym where it was done; the personal session
  # cannot read it without that gym's context (ADR-133).
  defp fetch_workout(organization_id, workout_id) do
    with {:ok, context} <-
           Organizations.resolve_system_tenant_context(organization_id, :execution_history, %{
             service: __MODULE__
           }),
         %{} = workout <- Workouts.get_workout(context, workout_id) do
      workout
    else
      _unreachable -> nil
    end
  end

  defp sets(sets) when is_integer(sets) and sets > 0, do: sets
  defp sets(_sets), do: 1

  defp field(map, key), do: Map.get(map, key, Map.get(map, Atom.to_string(key)))
end
