defmodule MilosTraining.Application.GetMaterializedWorkout do
  alias MilosTraining.Workouts

  def call(id) do
    case Workouts.materialize_workout(id) do
      nil -> {:error, :not_found}
      payload -> {:ok, payload}
    end
  end

  def call(context, id) do
    case Workouts.get_workout(context, id) do
      nil ->
        {:error, :not_found}

      workout ->
        {:ok,
         %{
           workout: workout,
           scales: MilosTraining.Workouts.Domain.WorkoutMaterializer.materialize_all(workout)
         }}
    end
  end
end
