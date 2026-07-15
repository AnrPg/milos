defmodule MilosTraining.Application.GetCoachingAggregates do
  alias MilosTraining.Coaching

  def call, do: {:ok, Coaching.get_aggregates()}
end
