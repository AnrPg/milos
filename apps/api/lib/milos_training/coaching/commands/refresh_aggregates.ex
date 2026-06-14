defmodule MilosTraining.Coaching.Commands.RefreshAggregates do
  alias MilosTraining.Coaching.CoachingStore

  def call, do: CoachingStore.refresh_aggregates()
end
