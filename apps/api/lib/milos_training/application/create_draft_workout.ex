defmodule MilosTraining.Application.CreateDraftWorkout do
  alias MilosTraining.Workouts

  def call(admin) do
    with {:ok, draft} <- Workouts.create_draft(admin) do
      {:ok, draft}
    end
  end
end
