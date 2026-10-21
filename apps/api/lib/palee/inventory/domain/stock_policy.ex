defmodule Palee.Inventory.Domain.StockPolicy do
  @moduledoc """
  Whether a consumable is running low (ADR-104). What matters is how many days
  the stock lasts, not the count: two of something used once a year is plenty,
  two of something used daily is critical.

  The daily use comes from the item's own history once it has at least
  three uses recorded over two weeks or more; until then from its consumption
  speed (fast ≈ daily, regular ≈ weekly, slow ≈ quarterly). A reorder level set
  on the item raises the status to at least `:low` when the count reaches it.
  """

  @speeds [:fast, :regular, :slow]
  @default_daily_use %{fast: 1.0, regular: 1 / 7, slow: 1 / 90}
  @critical_days 7
  @low_days 21
  @min_uses 3
  @min_span_days 14
  @window_days 180
  @rank %{ok: 0, low: 1, critical: 2, out: 3}

  def speeds, do: @speeds
  def window_days, do: @window_days
  def thresholds, do: %{critical_days: @critical_days, low_days: @low_days}

  @doc """
  Daily use from consumption `movements` (`%{kind, quantity, occurred_at}`)
  within the window, or the speed's default.
  """
  def daily_use(speed, movements, %DateTime{} = now) do
    since = DateTime.add(now, -@window_days * 86_400, :second)

    uses =
      Enum.filter(movements, fn movement ->
        movement.kind == :consume and DateTime.compare(movement.occurred_at, since) != :lt
      end)

    first = uses |> Enum.map(& &1.occurred_at) |> Enum.min(DateTime, fn -> nil end)
    span = first && DateTime.diff(now, first, :second) / 86_400

    if length(uses) >= @min_uses and span >= @min_span_days do
      {Enum.sum(Enum.map(uses, & &1.quantity)) / span, :observed}
    else
      {Map.fetch!(@default_daily_use, speed), :estimated}
    end
  end

  @doc "Stock status, days it lasts, and the daily use behind it."
  def assess(%{quantity: quantity, consumption_speed: speed} = supply, movements, now) do
    {rate, basis} = daily_use(speed, movements, now)
    days_left = if rate > 0, do: quantity / rate, else: nil
    reorder_level = Map.get(supply, :reorder_level)

    by_days =
      cond do
        quantity <= 0 -> :out
        days_left != nil and days_left < @critical_days -> :critical
        days_left != nil and days_left < @low_days -> :low
        true -> :ok
      end

    by_level = if is_integer(reorder_level) and quantity <= reorder_level, do: :low, else: :ok

    %{
      status: worse(by_days, by_level),
      days_left: days_left && Float.round(days_left * 1.0, 1),
      daily_use: Float.round(rate * 1.0, 3),
      basis: basis
    }
  end

  @doc "Whether going from `previous` to `current` should alert (only when it gets worse)."
  def alert?(previous, current), do: @rank[current] > @rank[previous || :ok] and current != :ok

  def worse(a, b), do: if(@rank[a] >= @rank[b], do: a, else: b)

  @doc "Quantity after a movement; consumption cannot go below zero."
  def apply_movement(quantity, :restock, amount) when amount > 0, do: {:ok, quantity + amount}

  def apply_movement(quantity, :consume, amount) when amount > 0 do
    if amount <= quantity, do: {:ok, quantity - amount}, else: {:error, :not_enough_stock}
  end

  def apply_movement(_quantity, :adjust, count) when is_integer(count) and count >= 0,
    do: {:ok, count}

  def apply_movement(_quantity, _kind, _amount), do: {:error, :invalid_movement}
end
