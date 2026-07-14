defmodule MilosTraining.Application.GetMaterializedWorkout do
  alias MilosTraining.Workouts

  def call(id) do
    case Workouts.materialize_workout(id) do
      nil -> {:error, :not_found}
      payload -> {:ok, payload}
    end
  end
end
