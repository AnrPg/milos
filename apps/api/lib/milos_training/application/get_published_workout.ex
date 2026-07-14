defmodule MilosTraining.Application.GetPublishedWorkout do
  alias MilosTraining.Workouts

  def call(id) do
    case Workouts.get_workout(id) do
      nil -> {:error, :not_found}
      workout -> {:ok, workout}
    end
  end
end
