defmodule MilosTraining.Workouts.Commands.SubstituteAssignmentWorkout do
  alias MilosTraining.Workouts.WorkoutStore

  def call(assignment_id, new_workout_id),
    do: WorkoutStore.substitute_assignment_workout(assignment_id, new_workout_id)
end
