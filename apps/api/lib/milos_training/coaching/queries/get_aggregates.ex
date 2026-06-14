defmodule MilosTraining.Coaching.Queries.GetAggregates do
  alias MilosTraining.Coaching.CoachingStore

  def call, do: CoachingStore.get_aggregates()
end
