defmodule MilosTraining.Application.GetMaterializedWorkout do
  alias MilosTraining.Workouts

  def call(context, id) do
    case Workouts.materialize_workout(context, id) do
      nil -> {:error, :not_found}
      payload -> {:ok, payload}
    end
  end
end
