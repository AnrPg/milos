defmodule MilosTraining.Application.SetWorkoutIcon do
  @moduledoc """
  A coach picks a workout's icon by hand (kept forever, never replaced by AI),
  or resets it to automatic, which asks for a fresh suggestion.
  """

  alias MilosTraining.Application.{BroadcastUserSync, SuggestWorkoutIcon}
  alias MilosTraining.{Organizations, Workouts}
  alias MilosTraining.Workouts.Domain.WorkoutIcon

  def call(context, workout_id, nil) do
    with {:ok, updated} <- Workouts.set_workout_icon(context, workout_id, nil, nil) do
      SuggestWorkoutIcon.enqueue(context, workout_id)
      broadcast_refresh(context, workout_id)
      {:ok, updated}
    end
  end

  def call(context, workout_id, icon) do
    with {:ok, icon} <- validate(icon),
         {:ok, updated} <- Workouts.set_workout_icon(context, workout_id, icon, "coach") do
      broadcast_refresh(context, workout_id)
      {:ok, updated}
    end
  end

  defp validate(icon) do
    case WorkoutIcon.normalize(icon) do
      {:ok, icon} -> {:ok, icon}
      :error -> {:error, :invalid_workout_icon}
    end
  end

  defp broadcast_refresh(%{organization_id: organization_id}, workout_id) do
    organization_id
    |> Organizations.list_staff_user_ids()
    |> BroadcastUserSync.for_users(["admin_workouts"],
      reason: "workout_icon_changed",
      payload: %{workout_id: workout_id}
    )
  end
end
