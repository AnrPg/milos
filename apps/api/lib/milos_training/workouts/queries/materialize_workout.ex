defmodule MilosTraining.Workouts.Queries.MaterializeWorkout do
  alias MilosTraining.Workouts.Domain.WorkoutMaterializer
  alias MilosTraining.Workouts.Queries.GetWorkout

  def by_id(id) do
    case GetWorkout.by_id(id) do
      nil ->
        nil

      workout ->
        %{
          workout: workout,
          scales: WorkoutMaterializer.materialize_all(workout)
        }
    end
  end
end
