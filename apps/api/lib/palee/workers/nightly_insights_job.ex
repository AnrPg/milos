defmodule Palee.Workers.NightlyInsightsJob do
  @moduledoc "Nightly: recomputes the Πρόοδος insights of everyone with recent data (ADR-166)."

  use Oban.Worker, queue: :analytics, max_attempts: 3, unique: [period: 3_600]

  alias Palee.Application.NightlyInsights

  @impl Oban.Worker
  def perform(_job) do
    {:ok, _count} = NightlyInsights.call()
    :ok
  end
end
