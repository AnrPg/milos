defmodule Palee.Workers.SignTillReceiptsJob do
  @moduledoc """
  ADR-251: signs due till receipts with the TSE (DE) or RKSV unit (AT) and
  reads back uncertain ones. With an `organization_id` it serves that
  tenant (right after an issue, a retry or a new connection); without one
  (cron, every 2 minutes) it sweeps every active organization, so a German
  receipt the TSE could not sign is recorded as a TSE failure soon after
  its outage window. Claims are row-locked, so overlapping runs are safe.
  """

  use Oban.Worker,
    queue: :fiscal,
    max_attempts: 3,
    unique: [period: 10, keys: [:organization_id, :signature_id]]

  require Logger

  alias Palee.Application.Fiscal.FiscalTillSigning
  alias Palee.Organizations

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"organization_id" => organization_id} = args})
      when is_binary(organization_id) do
    sign(organization_id, args["signature_id"] || :due)
  end

  def perform(_job) do
    Organizations.list_active_organizations_for_system()
    |> Enum.each(fn %{organization: organization} -> sign(organization.id, :due) end)

    :ok
  end

  defp sign(organization_id, which) do
    case FiscalTillSigning.transmit(%{organization_id: organization_id}, which) do
      {:ok, _counts} ->
        :ok

      error ->
        Logger.error("till signing failed for #{organization_id}: #{inspect(error)}")
        :ok
    end
  end
end
