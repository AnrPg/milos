defmodule Palee.Workers.TransmitFiscalDocumentsJob do
  @moduledoc """
  ADR-243: sends due fiscal documents to the tax authority. With an
  `organization_id` it serves that tenant (right after an issue, a retry or
  a new connection); without one (cron, every 5 minutes) it sweeps every
  active organization, so retries and deferrals never depend on a
  request. Claims are row-locked, so overlapping runs are safe.
  """

  use Oban.Worker,
    queue: :fiscal,
    max_attempts: 3,
    unique: [period: 30, keys: [:organization_id, :transmission_id]]

  require Logger

  alias Palee.Application.Fiscal.FiscalReporting
  alias Palee.Organizations

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"organization_id" => organization_id} = args})
      when is_binary(organization_id) do
    transmit(organization_id, args["transmission_id"] || :due)
  end

  def perform(_job) do
    Organizations.list_active_organizations_for_system()
    |> Enum.each(fn %{organization: organization} -> transmit(organization.id, :due) end)

    :ok
  end

  defp transmit(organization_id, which) do
    case FiscalReporting.transmit(%{organization_id: organization_id}, which) do
      {:ok, _counts} ->
        :ok

      error ->
        Logger.error("fiscal transmission failed for #{organization_id}: #{inspect(error)}")
        :ok
    end
  end
end
