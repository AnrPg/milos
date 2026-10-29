defmodule Palee.Application.AssignWorkoutToAthletes do
  @moduledoc """
  Assigns a library workout to one or more athletes. Each athlete receives their
  own copy, filed in `Athletes/<nickname>`, so the coach can personalise it
  without touching the library template or anyone else's programming. A workout
  already filed in the athlete's folder is assigned as-is.

  Athletes are processed in order; if one fails (e.g. their package has no
  programming left) the error is returned and athletes already handled keep
  their assignment.
  """

  alias Palee.Application.{
    AssignWorkout,
    AuthorizeProgramming,
    FileWorkoutCopy,
    ListAthletes,
    WorkoutLibraryFolders
  }

  def call(context, params) do
    workout_id = value(params, :master_workout_id)
    athlete_ids = value(params, :athlete_ids)

    with false <- class_variant?(params),
         {:ok, athletes} <- tenant_athletes(context, athlete_ids),
         # ADR-225: before any copy is filed, so a refusal leaves no orphan.
         :ok <- AuthorizeProgramming.call(context, Enum.map(athletes, & &1.id)) do
      assign_each(context, params, workout_id, athletes)
    else
      true ->
        assign_directly(context, params)

      {:error, :invalid_athletes} when athlete_ids not in [nil, []] ->
        assign_directly(context, params)

      error ->
        error
    end
  end

  # ADR-125: members, mixed selections and class variants (a `source_slot_id`)
  # are classified, entitled and linked to their class by `AssignWorkout`; only
  # a plain athlete selection gets a filed copy per athlete.
  defp assign_directly(context, params) do
    with {:ok, assignment} <- AssignWorkout.call(context, params), do: {:ok, [assignment]}
  end

  defp class_variant?(params) do
    case value(params, :source_slot_id) do
      slot_id when is_binary(slot_id) and slot_id != "" -> true
      _ -> false
    end
  end

  defp assign_each(context, params, workout_id, athletes) do
    athletes
    |> Enum.reduce_while({:ok, []}, fn athlete, {:ok, assignments} ->
      case assign_one(context, params, workout_id, athlete) do
        {:ok, assignment} -> {:cont, {:ok, [assignment | assignments]}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, assignments} -> {:ok, Enum.reverse(assignments)}
      error -> error
    end
  end

  defp assign_one(context, params, workout_id, athlete) do
    with {:ok, folder} <- WorkoutLibraryFolders.athlete_folder(context, athlete),
         {:ok, workout} <- FileWorkoutCopy.ensure_in_folder(context, workout_id, folder.id) do
      context
      |> AssignWorkout.call(%{
        master_workout_id: workout.id,
        athlete_ids: [athlete.id],
        scheduled_for: value(params, :scheduled_for),
        instructions: value(params, :instructions),
        all_locations: value(params, :all_locations),
        location_ids: value(params, :location_ids)
      })
      |> case do
        {:ok, assignment} ->
          {:ok, assignment}

        error ->
          FileWorkoutCopy.discard(context, workout, workout_id)
          error
      end
    end
  end

  defp tenant_athletes(context, athlete_ids) do
    ids = athlete_ids |> List.wrap() |> Enum.uniq()

    by_id =
      case ListAthletes.call(context, nil) do
        athletes when is_list(athletes) -> Map.new(athletes, &{&1.id, &1})
        _error -> %{}
      end

    if ids != [] and Enum.all?(ids, &Map.has_key?(by_id, &1)),
      do: {:ok, Enum.map(ids, &Map.fetch!(by_id, &1))},
      else: {:error, :invalid_athletes}
  end

  defp value(map, key) do
    case Map.fetch(map, key) do
      {:ok, value} -> value
      :error -> Map.get(map, Atom.to_string(key))
    end
  end
end
