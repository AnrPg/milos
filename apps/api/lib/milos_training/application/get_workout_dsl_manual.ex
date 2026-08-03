defmodule MilosTraining.Application.GetWorkoutDslManual do
  @moduledoc false

  alias MilosTraining.Workouts

  def call, do: {:ok, Workouts.dsl_manual()}
end
