defmodule Palee.Application.FileWorkoutCopy do
  @moduledoc """
  Files a workout into a library folder the way a coach would copy a file:
  the copy keeps the original title and is published when the original is, so
  it can be assigned straight away. Library templates stay untouched.
  """

  alias Palee.Application.DuplicateWorkout
  alias Palee.Workouts

  @doc """
  Returns a published workout that lives in `folder_id`: the workout itself when
  it is already filed there, otherwise a fresh copy.

  With `reuse_copy: true` a published copy of the same workout already filed in
  the folder is reused (e.g. several classes on the same day share one WOD).
  """
  def ensure_in_folder(context, workout_id, folder_id, opts \\ []) do
    case Workouts.get_workout_for_admin(context, workout_id) do
      nil -> {:error, :workout_not_found}
      %{folder_id: ^folder_id} = workout -> {:ok, workout}
      _elsewhere -> reuse_or_copy(context, workout_id, folder_id, opts[:reuse_copy] == true)
    end
  end

  defp reuse_or_copy(context, workout_id, folder_id, true) do
    case Workouts.find_filed_copy(context, workout_id, folder_id) do
      nil ->
        copy(context, workout_id, folder_id, copy_goals: false)

      # Marked so a failed follow-up step never deletes a copy other classes use.
      copy_id ->
        {:ok, context |> Workouts.get_workout_for_admin(copy_id) |> Map.put(:reused, true)}
    end
  end

  defp reuse_or_copy(context, workout_id, folder_id, false),
    do: copy(context, workout_id, folder_id, copy_goals: false)

  @doc "Deletes a copy made by `ensure_in_folder/3` when the step it was made for failed."
  def discard(_context, %{id: id}, id), do: :ok
  def discard(_context, %{reused: true}, _original_id), do: :ok

  def discard(context, %{id: copy_id}, _original_id) do
    _result = Workouts.delete_workout(context, copy_id)
    :ok
  end

  @doc """
  Copies a workout into `folder_id` (`nil` = library root). An explicit copy
  takes the original's WOD goals; the programming copies `ensure_in_folder/4`
  makes pass `copy_goals: false` and inherit them instead (ADR-163).
  """
  def copy(context, workout_id, folder_id, opts \\ []) do
    with %{} = source <-
           Workouts.get_workout_for_admin(context, workout_id) || {:error, :workout_not_found},
         {:ok, draft} <-
           DuplicateWorkout.call(context, workout_id,
             folder_id: folder_id,
             title_suffix: title_suffix(source, folder_id),
             copy_goals: Keyword.get(opts, :copy_goals, true)
           ) do
      maybe_publish(context, source, draft)
    end
  end

  # A copy dropped next to its original gets "(copy)" so the two can be told apart.
  defp title_suffix(%{folder_id: folder_id}, folder_id), do: "(copy)"
  defp title_suffix(_source, _folder_id), do: ""

  defp maybe_publish(context, %{status: status}, draft) when status in [:published, "published"],
    do: Workouts.publish_workout(context, draft.id, %{expected_source_revision: 0})

  defp maybe_publish(context, _source, draft),
    do: {:ok, Workouts.get_workout_for_admin(context, draft.id) || draft}
end
