defmodule MilosTraining.Application.GetAdminWorkout do
  alias MilosTraining.Workouts

  def call(id) do
    case Workouts.get_workout_for_admin(id) do
      nil -> {:error, :not_found}
      workout -> {:ok, workout}
    end
  end

  def call(context, id) do
    case Workouts.get_workout_for_admin(context, id) do
      nil -> {:error, :not_found}
      workout -> {:ok, workout}
    end
  end
end
