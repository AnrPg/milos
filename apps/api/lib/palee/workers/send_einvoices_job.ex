defmodule Palee.Workers.SendEInvoicesJob do
  @moduledoc """
  ADR-250: sends due Peppol submissions and polls their delivery. With an
  `organization_id` it serves that tenant (right after an issue, a retry,
  a new connection or a webhook); without one (cron, every 5 minutes) it
  sweeps every active organization. Claims are row-locked, so overlapping
  runs are safe.
  """

  use Oban.Worker,
    queue: :fiscal,
    max_attempts: 3,
    unique: [period: 30, keys: [:organization_id, :submission_id]]

  require Logger

  alias Palee.Application.Fiscal.FiscalEInvoicing
  alias Palee.Organizations

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"organization_id" => organization_id} = args})
      when is_binary(organization_id) do
    transmit(organization_id, args["submission_id"] || :due)
  end

  def perform(_job) do
    Organizations.list_active_organizations_for_system()
    |> Enum.each(fn %{organization: organization} -> transmit(organization.id, :due) end)

    :ok
  end

  # Transmission always answers with counts; a crash is logged, never retried here.
  defp transmit(organization_id, which) do
    {:ok, _counts} = FiscalEInvoicing.transmit(%{organization_id: organization_id}, which)
    :ok
  rescue
    error ->
      Logger.error("Peppol sending failed for #{organization_id}: #{Exception.message(error)}")
      :ok
  end
end
