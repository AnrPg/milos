defmodule Palee.Shop.Ports.ShopReportStore do
  @moduledoc """
  Read model of the shop reports (ADR-192 §4-6). Every callback runs in the
  caller's tenant session (`RepoContext.run/2`) and aggregates in the
  database: it returns groups (per day, product, channel...), never one row
  per order, so a report costs the same for ten orders or a million.

  `filters` is `%{from_at, to_at, zone, location_ids}`: the UTC bounds of the
  gym-local days `[from, to]` (`from_at` inclusive, `to_at` exclusive, from
  `ZonedTime.start_of_day/2`), the gym's zone for day bucketing, and the
  branches to keep (`nil` = all). Orders count from the moment they were
  paid; refunds belong to the sale they refund.
  """

  @type filters :: %{
          from_at: DateTime.t(),
          to_at: DateTime.t(),
          zone: String.t(),
          location_ids: [Ecto.UUID.t()] | nil
        }

  @type dimension :: :channel | :location_id | :promotion_code | :campaign_id | :source

  @doc "`[%{day, currency, orders, gross_cents, refunded_cents}]` per gym-local day."
  @callback sales_by_day(filters()) :: [map()]

  @doc "Order groups `%{orders, gross_cents, refunded_cents}` plus the dimension's key(s)."
  @callback order_groups(filters(), dimension()) :: [map()]

  @doc "Line groups per variant: units, revenue, refunds and the costed part of both."
  @callback line_groups(filters()) :: [map()]

  @doc "Stock rows per variant and branch, with the units sold in the window."
  @callback stock(filters()) :: [map()]

  @doc """
  The pricing inputs per live variant: price, cost, category, stock, the
  price periods of the window (from the price ledger) with the units sold in
  each, and discounted versus full-price sales.
  """
  @callback pricing_inputs(filters()) :: [map()]

  @doc "Target margins: `%{category | nil => basis_points}`."
  @callback pricing_targets() :: %{optional(String.t() | nil) => non_neg_integer()}

  @doc "Sets (or clears with `nil`) the target margin of a category (`nil` = default)."
  @callback put_pricing_target(String.t() | nil, non_neg_integer() | nil, Ecto.UUID.t() | nil) ::
              :ok | {:error, term()}

  @doc """
  The three reconciliation figures per `{day, currency}`:
  `%{orders: map, invoice_lines: map, payments: map}`.
  """
  @callback reconciliation_figures(filters()) :: %{
              orders: %{{Date.t(), String.t()} => integer()},
              invoice_lines: %{{Date.t(), String.t()} => integer()},
              payments: %{{Date.t(), String.t()} => integer()}
            }
end
