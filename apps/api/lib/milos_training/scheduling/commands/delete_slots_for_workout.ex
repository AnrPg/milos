defmodule MilosTraining.Scheduling.Commands.DeleteSlotsForWorkout do
  alias MilosTraining.Scheduling.SchedulingStore

  def call(workout_id), do: SchedulingStore.delete_slots_for_workout(workout_id)
end
