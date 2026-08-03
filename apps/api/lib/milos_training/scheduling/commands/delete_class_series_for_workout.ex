defmodule MilosTraining.Scheduling.Commands.DeleteClassSeriesForWorkout do
  alias MilosTraining.Scheduling.SchedulingStore

  def call(workout_id), do: SchedulingStore.delete_class_series_for_workout(workout_id)
end
