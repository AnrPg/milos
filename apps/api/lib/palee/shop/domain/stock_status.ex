defmodule Palee.Shop.Domain.StockStatus do
  @moduledoc """
  Whether a variant is running low (ADR-190), on ADR-104's terms: what
  matters is how many days the available stock lasts at the recent sales
  rate (`Inventory.Domain.StockPolicy` thresholds: critical under 7 days, low
  under 21), and a per-variant `low_stock_threshold` raises the status to at
  least `:low` when available stock reaches it.

  The rate is observed from sales in the last 90 days once there are at
  least three sales spanning two weeks; before that only the threshold and
  "out" apply (a new product is never "critical" from a guess).
  """

  alias Palee.Inventory.Domain.StockPolicy

  @statuses [:ok, :low, :critical, :out]
  @window_days 90
  @min_sales 3
  @min_span_days 14

  @spec statuses() :: [atom()]
  def statuses, do: @statuses

  @spec window_days() :: pos_integer()
  def window_days, do: @window_days

  @doc """
  Status of `available` units given `sales` (`%{quantity, occurred_at}`, the
  quantity negative as in the ledger) and the variant's threshold.
  """
  @spec assess(integer(), [map()], non_neg_integer() | nil, DateTime.t()) :: map()
  def assess(available, sales, threshold, %DateTime{} = now) do
    rate = daily_rate(sales, now)
    days_left = if rate && rate > 0, do: Float.round(available / rate, 1), else: nil
    %{critical_days: critical, low_days: low} = StockPolicy.thresholds()

    by_days =
      cond do
        available <= 0 -> :out
        days_left != nil and days_left < critical -> :critical
        days_left != nil and days_left < low -> :low
        true -> :ok
      end

    by_threshold = if is_integer(threshold) and available <= threshold, do: :low, else: :ok

    %{
      status: StockPolicy.worse(by_days, by_threshold),
      days_left: days_left,
      daily_rate: rate && Float.round(rate, 3)
    }
  end

  @doc "Units sold per day over the window, or nil without enough history."
  @spec daily_rate([map()], DateTime.t()) :: float() | nil
  def daily_rate(sales, now) do
    since = DateTime.add(now, -@window_days * 86_400, :second)

    recent =
      Enum.filter(sales, fn sale ->
        sale.quantity < 0 and DateTime.compare(sale.occurred_at, since) != :lt
      end)

    first = recent |> Enum.map(& &1.occurred_at) |> Enum.min(DateTime, fn -> nil end)
    span = first && DateTime.diff(now, first, :second) / 86_400

    if length(recent) >= @min_sales and span >= @min_span_days,
      do: -Enum.sum(Enum.map(recent, & &1.quantity)) / span,
      else: nil
  end

  @doc "Whether going from `previous` to `current` alerts staff (only when it gets worse)."
  @spec alert?(atom() | nil, atom()) :: boolean()
  def alert?(previous, current), do: StockPolicy.alert?(previous, current)
end
