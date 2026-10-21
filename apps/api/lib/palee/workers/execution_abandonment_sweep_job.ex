defmodule Palee.Workers.ExecutionAbandonmentSweepJob do
  @moduledoc """
  Hourly Oban cron (ADR-123): records `workout_execution_abandoned` for every
  active tenant via `SweepAbandonedExecutions`, one tenant session at a time.
  Safe to re-run; the sweep is idempotent per execution.
  """

  use Oban.Worker,
    queue: :analytics,
    max_attempts: 3,
    unique: [period: 3_000, states: [:available, :scheduled, :executing]]

  alias Palee.Organizations
  alias Palee.Application.SweepAbandonedExecutions

  @impl Oban.Worker
  def perform(_job) do
    now = DateTime.utc_now()

    Organizations.list_active_organizations_for_system()
    |> Enum.each(fn %{organization: organization} ->
      SweepAbandonedExecutions.call(organization.id, now)
    end)

    :ok
  end
end
