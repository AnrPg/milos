defmodule Palee.Application.GetGoalFeedbackSummary do
  @moduledoc """
  Coach totals of «τι ένιωσες» on a workout or a scheduled class (ADR-163,
  board 18 Q6): how many entries carry feedback, which muscle groups and
  qualities were felt and how often, and which goal groups nobody felt.

  Only feedback the acting staff member may read counts: the rows are read
  in their own session, so the `goal_feedback` coach read policies apply
  (the entry's rung must reach a coach of this gym, or the entry is shared
  with it, ADR-139/ADR-162). Voided entries never count. Below three such
  entries nothing but the count is returned (`shown: false`), so no single
  member's answers can be read off the totals.

  For a workout, entries on that workout; for a class, entries logged from
  it or timed from one of its bookings, whatever version of the workout
  they followed. Goals are the workout's own or inherited ones (for a
  class, its workout's).
  """

  alias Palee.{Anatomy, Journal, Scheduling, Workouts}

  def for_workout(context, workout_id) do
    with {:ok, workout_id} <- cast_id(workout_id),
         %{} <- Workouts.get_workout_for_admin(context, workout_id) || {:error, :not_found} do
      rows = Journal.list_goal_feedback_for(context, {:workout, workout_id})
      {:ok, Map.put(summary(context, rows, workout_id), :workout_id, workout_id)}
    end
  end

  def for_scheduled_class(context, slot_id) do
    with {:ok, slot_id} <- cast_id(slot_id),
         %{} = slot <- Scheduling.get_slot(context, slot_id) || {:error, :not_found} do
      rows = Journal.list_goal_feedback_for(context, {:scheduled_class, slot_id})

      {:ok,
       context
       |> summary(rows, slot.master_workout_id)
       |> Map.merge(%{scheduled_class_id: slot_id, workout_id: slot.master_workout_id})}
    end
  end

  defp summary(context, rows, workout_id) do
    Anatomy.summarize_feedback(rows, goal_muscles(context, workout_id))
  end

  defp goal_muscles(_context, nil), do: []

  defp goal_muscles(context, workout_id) do
    case Workouts.resolve_workout_goals(context, workout_id) do
      %{goals: %{muscles: muscles}} -> muscles
      _none -> []
    end
  end

  defp cast_id(id) do
    case Ecto.UUID.cast(id) do
      {:ok, id} -> {:ok, id}
      :error -> {:error, :not_found}
    end
  end
end
