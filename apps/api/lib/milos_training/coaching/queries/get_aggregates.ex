defmodule MilosTraining.Coaching.Queries.GetAggregates do
  alias MilosTraining.Coaching.CoachingStore

  def call(context), do: CoachingStore.with_tenant_context(context, &call/0)
  def call, do: CoachingStore.get_aggregates()
end
