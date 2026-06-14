defmodule MilosTraining.Coaching do
  alias MilosTraining.Coaching.Commands.RefreshAggregates
  alias MilosTraining.Coaching.Queries.GetAggregates

  defdelegate get_aggregates(), to: GetAggregates, as: :call
  defdelegate refresh_aggregates(), to: RefreshAggregates, as: :call
end
