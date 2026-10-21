defmodule Palee.Application.AthleteTrainingVolume do
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
  nil when not recognised). Each performance also carries its `source`
  token (the organization id, `freeform` or `device`, as the Πρόοδος source
  filter takes it), its `minutes` and its perceived effort `rpe` (training
  log only; executions record no effort), for training load (ADR-165), and
  the zone it was recorded in (`tz`), for the part of the day insights read
  (ADR-166).

  A coach of one gym reads a client through `scope: {:coach, organization_id}`
  in the coach's tenant session (ADR-165): only the client's executions and
  log entries on a rung that reaches that gym's coaches, shared with it
  (ADR-139, ADR-162), and only the felt feedback row security admits. A workout is read once per window, in its own
  organization's context (like `ListWorkoutExecutions`); one that cannot be
  read any more contributes nothing.
  """

  alias Palee.{Execution, Journal, Organizations, Workouts}

  @log_limit 2_000

  @type performance :: %{
          kind: String.t(),
          id: Ecto.UUID.t(),
          organization_id: Ecto.UUID.t() | nil,
          at: DateTime.t(),
          tz: String.t() | nil,
          source: String.t(),
          minutes: float() | nil,
          rpe: 1..10 | nil,
          exercises: [
            %{exercise_ref: String.t() | nil, name: String.t() | nil, sets: pos_integer()}
          ]
        }

  @doc """
  `%{performances: [performance], felt: [%{entry_kind, entry_id, felt_muscles,
  felt_qualities}]}` for everything done at or after `since` (a `DateTime`,
  or nil for everything).

  Options: `:user_id` (whose training; the caller by default) and `:scope`
  (`:owner`, the default, or `{:coach, organization_id}`).
  """
  def load(context, since, opts \\ []) do
    user_id = Keyword.get(opts, :user_id, context.user_id)
    scope = Keyword.get(opts, :scope, :owner)

    {executions, logs, felt} =
      Execution.with_execution_context(context, fn ->
        executions =
          user_id
          |> list_executions(scope)
          |> Enum.filter(&completed_since?(&1, since))

        logs =
          user_id
          |> Execution.list_training_log_items(:none, @log_limit, scope)
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

  defp list_executions(user_id, :owner), do: Execution.list_executions_for_user(user_id)

  defp list_executions(user_id, scope),
    do: Execution.list_execution_items(user_id, :none, @log_limit, scope)

  defp completed_since?(execution, since) do
    to_string(execution.status) == "completed" and match?(%DateTime{}, execution.completed_at_utc) and
      on_or_after?(execution.completed_at_utc, since)
  end

  defp logged_since?(entry, since) do
    Map.get(entry, :status, "logged") == "logged" and match?(%DateTime{}, entry.performed_at_utc) and
      on_or_after?(entry.performed_at_utc, since)
  end

  defp on_or_after?(_at, nil), do: true
  defp on_or_after?(at, since), do: DateTime.compare(at, since) != :lt

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
      tz: Map.get(execution, :completed_at_tz) || Map.get(execution, :started_at_tz),
      source: source(execution.organization_id, nil),
      minutes: minutes_from_ms(Map.get(execution, :total_elapsed_ms)),
      rpe: nil,
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
      tz: Map.get(entry, :performed_at_tz),
      source: source(entry.organization_id, Map.get(entry, :source_type)),
      minutes: minutes_from_seconds(Map.get(entry, :duration_seconds)),
      rpe: rpe(Map.get(entry, :perceived_effort)),
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

  # The Πρόοδος source token (ADR-162, `EntrySource`): a device first, then
  # the provider, else freeform.
  defp source(organization_id, source_type) do
    cond do
      Journal.device_source?(source_type) -> "device"
      is_binary(organization_id) -> organization_id
      true -> "freeform"
    end
  end

  defp minutes_from_ms(ms) when is_integer(ms) and ms > 0, do: ms / 60_000
  defp minutes_from_ms(_ms), do: nil

  defp minutes_from_seconds(seconds) when is_integer(seconds) and seconds > 0, do: seconds / 60
  defp minutes_from_seconds(_seconds), do: nil

  defp rpe(effort) when is_integer(effort) and effort in 1..10, do: effort
  defp rpe(_effort), do: nil

  defp field(map, key), do: Map.get(map, key, Map.get(map, Atom.to_string(key)))
end
