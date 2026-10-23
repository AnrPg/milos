defmodule Palee.Shop.Domain.TenantDataPolicy do
  @moduledoc """
  Shop tenant data retention and purge policy (ADR-117, ADR-190).

  Orders and their lines are the source rows of Finance's shop revenue
  (`source_type` / `source_id`), so they are retained with Finance's
  accounting records; the catalog and stock ledger go with them.
  """

  alias Palee.TenantData.Domain.RetentionReview

  @policy RetentionReview.normalize!(%{
            context: "shop",
            purge_order: 84,
            disposition: :retain,
            retain_years: 10,
            basis:
              "Shop orders and their lines are the source documents of shop revenue in Finance (invoice lines and payments point at them), so they follow Finance's statutory retention; the catalog and the stock ledger they reference are kept with them.",
            tables: [
              %{table: "shop_order_lines"},
              %{table: "shop_orders"},
              %{table: "shop_promotion_codes"},
              %{table: "shop_stock_alerts"},
              %{table: "shop_stock_movements"},
              %{table: "shop_stock_levels"},
              %{table: "shop_variants"},
              %{table: "shop_products"}
            ]
          })

  def policy, do: @policy
end
