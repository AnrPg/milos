defmodule MilosTraining.Application.UpdateDraftWorkout do
  alias MilosTraining.Workouts

  def call(id, params) do
    with {:ok, draft} <- Workouts.update_draft(id, params) do
      {:ok, draft}
    end
  end
end
