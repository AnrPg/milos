defmodule MilosTraining.Application.ListAdminWorkouts do
  alias MilosTraining.Workouts

  def call, do: {:ok, Workouts.list_workouts()}
end
