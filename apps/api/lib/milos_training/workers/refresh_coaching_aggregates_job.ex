defmodule MilosTraining.Workers.RefreshCoachingAggregatesJob do
  use Oban.Worker, queue: :analytics, max_attempts: 3

  alias MilosTraining.Coaching

  @impl Oban.Worker
  def perform(_job), do: Coaching.refresh_aggregates()
end
