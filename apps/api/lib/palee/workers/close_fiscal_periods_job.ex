defmodule Palee.Workers.CloseFiscalPeriodsJob do
  @moduledoc """
  ADR-242: closes every gym-local day, month and year that has ended, for
  every gym (hourly, so each time zone closes on its own clock). Idempotent:
  a closed period is never closed again.
  """

  use Oban.Worker, queue: :analytics, max_attempts: 3

  require Logger

  alias Palee.Application.Fiscal.FiscalAdmin
  alias Palee.Organizations

  @impl Oban.Worker
  def perform(_job) do
    Organizations.list_active_organizations_for_system()
    |> Enum.each(fn %{organization: organization} ->
      case FiscalAdmin.close_due_periods(%{organization_id: organization.id}) do
        {:ok, _closings} ->
          :ok

        {:error, reason} ->
          Logger.error("fiscal closing failed for #{organization.id}: #{inspect(reason)}")
      end
    end)

    :ok
  end
end
