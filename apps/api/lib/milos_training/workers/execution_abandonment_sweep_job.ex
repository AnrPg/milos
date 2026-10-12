defmodule MilosTraining.Workers.ExecutionAbandonmentSweepJob do
  @moduledoc """
  Hourly Oban cron (ADR-105): records `workout_execution_abandoned` for every
  active tenant via `SweepAbandonedExecutions`, one tenant session at a time.
  Safe to re-run; the sweep is idempotent per execution.
  """

  use Oban.Worker,
    queue: :analytics,
    max_attempts: 3,
    unique: [period: 3_000, states: [:available, :scheduled, :executing]]

  alias MilosTraining.Application.SweepAbandonedExecutions
  alias MilosTraining.Organizations.OrganizationStore

  @impl Oban.Worker
  def perform(_job) do
    now = DateTime.utc_now()

    OrganizationStore.list_organizations()
    |> Enum.filter(fn %{organization: organization} -> organization.status == :active end)
    |> Enum.each(fn %{organization: organization} ->
      SweepAbandonedExecutions.call(organization.id, now)
    end)

    :ok
  end
end
