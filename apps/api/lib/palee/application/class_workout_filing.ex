defmodule Palee.Application.ClassWorkoutFiling do
  @moduledoc """
  Files the workout of a dated class in `Classes/<year>/<month>/<date>`.

  Filing happens only when a workout is *assigned* to an existing class (or a
  class's workout is changed). Creating classes never files anything, so the
  Classes tree only holds days that actually had a workout programmed, instead
  of filling up with placeholder copies for every scheduled class.

  The class gets its own copy in that day's folder, leaving the template
  untouched. A workout already filed in the day's folder (e.g. created
  specifically for the class) is used as-is, and classes on the same day share
  one copy.
  """

  alias Palee.Application.{FileWorkoutCopy, WorkoutLibraryFolders}

  @doc """
  Runs `persist.(context, params)` with `master_workout_id` swapped for the
  filed workout, and discards a fresh copy if persisting fails. Nothing is
  filed when the workout is unchanged from `current_workout_id`.
  """
  def with_filed_workout(context, params, persist, current_workout_id \\ nil) do
    workout_id = value(params, :master_workout_id)

    if is_nil(workout_id) or workout_id == current_workout_id do
      persist.(context, params)
    else
      case WorkoutLibraryFolders.class_day_folder(context, value(params, :scheduled_at)) do
        {:ok, folder} -> file_and_persist(context, params, persist, workout_id, folder.id)
        # Let slot validation report a missing or malformed time.
        {:error, :invalid_scheduled_at} -> persist.(context, params)
        error -> error
      end
    end
  end

  defp file_and_persist(context, params, persist, workout_id, folder_id) do
    with {:ok, filed} <-
           FileWorkoutCopy.ensure_in_folder(context, workout_id, folder_id, reuse_copy: true) do
      context
      |> persist.(put_value(params, :master_workout_id, filed.id))
      |> case do
        {:ok, result} ->
          {:ok, result}

        error ->
          FileWorkoutCopy.discard(context, filed, workout_id)
          error
      end
    end
  end

  defp value(map, key) do
    case Map.fetch(map, key) do
      {:ok, value} -> value
      :error -> Map.get(map, Atom.to_string(key))
    end
  end

  defp put_value(map, key, value) do
    if Map.has_key?(map, Atom.to_string(key)),
      do: Map.put(map, Atom.to_string(key), value),
      else: Map.put(map, key, value)
  end
end
