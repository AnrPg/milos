defmodule MilosTraining.Workers.FinalizeScanCheckInJob do
  @moduledoc """
  Consumes the open-gym visit of a door or desk scan once its undo minute has
  passed (ADR-155). An undone check-in is gone by then, so the job finds
  nothing and does nothing; a reservation that is already closed is left as
  it is. If the job never runs, the visit simply stays reserved, which
  counts as used.
  """

  use Oban.Worker,
    queue: :default,
    max_attempts: 10,
    unique: [keys: [:check_in_id], period: :infinity, states: :incomplete]

  require Logger

  alias MilosTraining.Application.{CheckInOpenGym, OwnershipKeys}

  @undo_seconds 60
  @margin_seconds 5

  @doc "Schedules the finalize step after the undo minute (no-op without Oban)."
  def schedule(organization_id, check_in_id) do
    if Oban.whereis(Oban) do
      %{organization_id: organization_id, check_in_id: check_in_id}
      |> new(schedule_in: @undo_seconds + @margin_seconds)
      |> Oban.insert()
      |> case do
        {:ok, _job} -> :ok
        {:error, reason} -> Logger.warning("scan_finalize_schedule_failed #{inspect(reason)}")
      end
    end

    :ok
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    with {:ok, %{"organization_id" => organization_id, "check_in_id" => check_in_id}} <-
           OwnershipKeys.require_tenant_args(args) do
      CheckInOpenGym.finalize_deferred(%{organization_id: organization_id}, check_in_id)
    end
  end
end
