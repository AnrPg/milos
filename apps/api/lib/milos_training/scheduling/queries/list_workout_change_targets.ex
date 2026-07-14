defmodule MilosTraining.Scheduling.Queries.ListWorkoutChangeTargets do
  alias MilosTraining.Scheduling.SchedulingStore

  def for_workout(workout_id), do: SchedulingStore.list_workout_change_targets(workout_id)
  def slot_ids_for_workout(workout_id), do: SchedulingStore.list_slot_ids_for_workout(workout_id)
end
