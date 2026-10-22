defmodule Palee.Application.LinkClassWorkout do
  @moduledoc """
  Links a WOD to a class created without one (ADR-176). A draft class is
  published by it; a series occurrence loses its incomplete badge and stops
  alerting staff. The WOD is filed in the day's Classes folder exactly as
  when a class is edited (`ClassWorkoutFiling`).
  """

  alias Palee.Application.{ClassWorkoutFiling, ScheduleRealtime, TrackAnalyticsEvent}
  alias Palee.{Scheduling, Workouts}

  def call(%{organization_id: _} = context, slot_id, workout_id) do
    with {:ok, slot} <- fetch_slot(context, slot_id),
         {:ok, _workout} <- fetch_workout(context, workout_id),
         {:ok, _linked} <-
           ClassWorkoutFiling.with_filed_workout(
             context,
             %{master_workout_id: workout_id, scheduled_at: slot.scheduled_at},
             &substitute(&1, slot.id, &2),
             slot.master_workout_id
           ),
         {:ok, updated} <- fetch_slot(context, slot.id) do
      ScheduleRealtime.broadcast("slot_updated", updated)

      TrackAnalyticsEvent.call("class_workout_linked", context, updated, %{
        metadata: %{was_published: Scheduling.class_published?(slot)}
      })

      {:ok, updated}
    end
  end

  def call(_context, _slot_id, _workout_id), do: {:error, :organization_context_required}

  defp substitute(context, slot_id, params),
    do: Scheduling.substitute_slot_workout(context, slot_id, params.master_workout_id)

  defp fetch_slot(context, id) do
    case Scheduling.get_slot(context, id) do
      %{} = slot -> {:ok, slot}
      _missing -> {:error, :not_found}
    end
  end

  defp fetch_workout(context, id) when is_binary(id) and id != "" do
    case Workouts.get_workout(context, id) do
      nil -> {:error, :workout_not_found}
      workout -> {:ok, workout}
    end
  end

  defp fetch_workout(_context, _id), do: {:error, :workout_not_found}
end
