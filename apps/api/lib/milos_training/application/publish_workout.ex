defmodule MilosTraining.Application.PublishWorkout do
  alias MilosTraining.Workouts

  def call(id, params) do
    with {:ok, workout} <- Workouts.publish_workout(id, params) do
      {:ok, workout}
    end
  end
end
