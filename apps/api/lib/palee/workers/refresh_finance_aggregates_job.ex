defmodule Palee.Workers.RefreshFinanceAggregatesJob do
  use Oban.Worker, queue: :analytics, max_attempts: 3

  alias Palee.Finance

  @impl Oban.Worker
  def perform(_job), do: Finance.refresh_aggregates()
end
