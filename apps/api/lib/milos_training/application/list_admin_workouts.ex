defmodule MilosTraining.Application.ListAdminWorkouts do
  alias MilosTraining.Workouts

  def call(context), do: {:ok, Workouts.list_workouts(context)}
end
