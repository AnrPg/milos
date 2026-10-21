defmodule Palee.Scheduling.Commands.DeleteSlotsForWorkout do
  alias Palee.Scheduling.SchedulingStore

  def call(context, workout_id), do: SchedulingStore.delete_slots_for_workout(context, workout_id)
  def call(workout_id), do: SchedulingStore.delete_slots_for_workout(workout_id)
end
