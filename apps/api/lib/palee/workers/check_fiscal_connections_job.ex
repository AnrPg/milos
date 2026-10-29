defmodule Palee.Workers.CheckFiscalConnectionsJob do
  @moduledoc """
  ADR-273: the scheduled «Δοκιμή σύνδεσης». Every hour it sweeps every
  active organization and checks the fiscal connections that are due:
  each one about every 3 months, sooner after a failure (1 h, 6 h, 1 day,
  3 days, then weekly after a refusal). A connection that becomes invalid
  notifies the staff who manage billing. With an `organization_id` it
  serves that tenant only.
  """

  use Oban.Worker,
    queue: :fiscal,
    max_attempts: 3,
    unique: [period: 300, keys: [:organization_id]]

  require Logger

  alias Palee.Application.Fiscal.FiscalConnections
  alias Palee.Organizations

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"organization_id" => organization_id}})
      when is_binary(organization_id) do
    check(organization_id)
  end

  def perform(_job) do
    Organizations.list_active_organizations_for_system()
    |> Enum.each(fn %{organization: organization} -> check(organization.id) end)

    :ok
  end

  # One box's failure never stops the sweep; it is logged, never retried here.
  defp check(organization_id) do
    {:ok, _checked} = FiscalConnections.check_due(%{organization_id: organization_id})
    :ok
  rescue
    error ->
      Logger.error(
        "fiscal connection check failed for #{organization_id}: #{Exception.message(error)}"
      )

      :ok
  end
end
