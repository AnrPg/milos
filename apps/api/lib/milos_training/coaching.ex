defmodule MilosTraining.Coaching do
  alias MilosTraining.Coaching.Commands.RefreshAggregates
  alias MilosTraining.Coaching.Queries.GetAggregates
  alias MilosTraining.Coaching.CoachingStore

  defdelegate get_aggregates(), to: GetAggregates, as: :call
  defdelegate get_aggregates(context), to: GetAggregates, as: :call
  defdelegate refresh_aggregates(), to: RefreshAggregates, as: :call
  defdelegate with_tenant_context(context, fun), to: CoachingStore
end
