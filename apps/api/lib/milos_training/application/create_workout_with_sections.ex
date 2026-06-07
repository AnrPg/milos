defmodule MilosTraining.Application.CreateWorkoutWithSections do
  alias MilosTraining.Workouts

  def call(admin, params) do
    with {:ok, workout} <- Workouts.create_workout(admin, params) do
      {:ok, workout}
    end
  end
end
