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

  defp maybe_publish(context, %{status: status} = source, draft)
       when status in [:published, "published"],
       do: publish_copy(context, draft, source)

  defp maybe_publish(context, _source, draft),
    do: {:ok, Workouts.get_workout_for_admin(context, draft.id) || draft}

  @doc """
  Publishes a fresh programming copy of `source`. A copy that cannot be
  published is deleted, so a failed assignment never leaves a stray draft in
  the folder, and the failure names the original WOD and what it lacks
  (`{:error, :workout_not_assignable, details}`), because that is where the
  coach has to fix it.
  """
  def publish_copy(context, %{id: draft_id}, source) do
    case Workouts.publish_workout(context, draft_id, %{expected_source_revision: 0}) do
      {:ok, published} ->
        {:ok, published}

      {:error, reason} ->
        _result = Workouts.delete_workout(context, draft_id)
        not_assignable(source, reason)
    end
  end

  defp not_assignable(source, reason) do
    case unpublishable_problem(reason) do
      nil ->
        {:error, reason}

      problem ->
        {:error, :workout_not_assignable,
         %{workout_id: source.id, title: Map.get(source, :title), problem: problem}}
    end
  end

  defp unpublishable_problem(:no_sections), do: "no_content"
  defp unpublishable_problem(:no_free_text_body), do: "no_content"
  defp unpublishable_problem({:invalid_text_sections, _problems}), do: "incomplete_sections"
  defp unpublishable_problem(%Ecto.Changeset{}), do: "invalid_details"
  defp unpublishable_problem(_reason), do: nil
end
