defmodule MilosTraining.Application.ListScaleLevels do
  alias MilosTraining.Workouts

  def call, do: Workouts.list_scale_levels()
end
