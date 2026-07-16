defmodule MilosTraining.Workouts.Domain.WorkoutType do
  @values [:crossfit, :strength, :gymnastics, :aerobics, :flexibility, :recovery]

  def values, do: @values
end
