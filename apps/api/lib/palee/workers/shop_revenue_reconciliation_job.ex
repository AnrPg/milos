defmodule Palee.Workers.ShopRevenueReconciliationJob do
  @moduledoc """
  Nightly shop revenue reconciliation for every active business (ADR-192
  §5): the last week of gym-local days, ending yesterday. Drift is logged
  (`shop_revenue_drift`) and counted (`palee_shop_reconciliation_*`), and
  the `PaleeShopRevenueDrift` alert fires on it. One business failing never
  stops the others.
  """

  use Oban.Worker, queue: :analytics, max_attempts: 3, unique: [period: 3_600]

  require Logger

  alias Palee.Application.ReconcileShopRevenue
  alias Palee.Organizations

  @impl Oban.Worker
  def perform(_job) do
    now = DateTime.utc_now()

    Organizations.list_active_organizations_for_system()
    |> Enum.each(fn %{organization: organization} ->
      try do
        ReconcileShopRevenue.nightly(%{organization_id: organization.id, user_id: nil}, now)
      rescue
        error ->
          Logger.error("shop_revenue_reconciliation_failed",
            event: "shop_revenue_reconciliation_failed",
            organization_id: organization.id,
            error: Exception.message(error)
          )
      end
    end)

    :ok
  end
end
