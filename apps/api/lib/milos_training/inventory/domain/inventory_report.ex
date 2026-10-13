defmodule MilosTraining.Inventory.Domain.InventoryReport do
  @moduledoc """
  How fast each consumable goes, what it costs, and what the inventory adds to
  the gym's expenses month by month (ADR-104). Purchases are restocks (at their
  recorded total, else quantity × unit price); machine costs are the costs
  logged on maintenance and repairs.
  """

  @doc """
  `supplies` carry `:movements`; `machine_events` carry `:cost_cents` and
  `:occurred_at`. Returns per-supply figures and a monthly expense series for
  the `months` up to `today`.
  """
  def build(supplies, machine_events, %Date{} = today, months) do
    month_keys = month_keys(today, months)
    from = month_start(List.first(month_keys))
    days = max(Date.diff(today, from) + 1, 1)

    per_supply =
      Enum.map(supplies, fn supply ->
        movements = Enum.filter(supply.movements, &in_range?(&1.occurred_at, from))
        consumed = sum_quantity(movements, :consume)
        purchases = Enum.filter(movements, &(&1.kind == :restock))
        spent = Enum.sum(Enum.map(purchases, &purchase_cents(&1, supply)))

        %{
          supply_id: supply.id,
          name: supply.name,
          unit: Map.get(supply, :unit),
          consumed: consumed,
          consumed_per_month: Float.round(consumed / days * 30, 2),
          purchased: sum_quantity(movements, :restock),
          spent_cents: spent,
          spent_per_month_cents: round(spent / days * 30),
          monthly:
            monthly(
              month_keys,
              purchases,
              &purchase_cents(&1, supply),
              &in_month?(&1.occurred_at, &2)
            )
        }
      end)

    supply_months =
      month_keys
      |> Enum.map(fn key ->
        {key, Enum.sum(Enum.map(per_supply, fn item -> month_value(item.monthly, key) end))}
      end)
      |> Map.new()

    machine_months =
      month_keys
      |> Map.new(fn key ->
        {key,
         machine_events
         |> Enum.filter(&in_month?(&1.occurred_at, key))
         |> Enum.map(&(&1.cost_cents || 0))
         |> Enum.sum()}
      end)

    %{
      from: from,
      to: today,
      supplies: Enum.sort_by(per_supply, & &1.spent_cents, :desc),
      expenses:
        Enum.map(month_keys, fn key ->
          %{
            month: key,
            supplies_cents: supply_months[key],
            machines_cents: machine_months[key],
            total_cents: supply_months[key] + machine_months[key]
          }
        end),
      totals: %{
        supplies_cents: Enum.sum(Map.values(supply_months)),
        machines_cents: Enum.sum(Map.values(machine_months))
      }
    }
  end

  def purchase_cents(%{total_cents: total}, _supply) when is_integer(total), do: total

  def purchase_cents(%{quantity: quantity} = movement, supply) do
    quantity * (Map.get(movement, :unit_price_cents) || Map.get(supply, :unit_price_cents) || 0)
  end

  defp monthly(keys, movements, value, in_month?) do
    Enum.map(keys, fn key ->
      %{
        month: key,
        cents: movements |> Enum.filter(&in_month?.(&1, key)) |> Enum.map(value) |> Enum.sum()
      }
    end)
  end

  defp month_value(monthly, key), do: Enum.find_value(monthly, 0, &(&1.month == key && &1.cents))

  defp sum_quantity(movements, kind),
    do: movements |> Enum.filter(&(&1.kind == kind)) |> Enum.map(& &1.quantity) |> Enum.sum()

  defp month_keys(today, months) do
    for offset <- (months - 1)..0//-1 do
      date = today |> Date.beginning_of_month() |> shift_months(-offset)
      Calendar.strftime(date, "%Y-%m")
    end
  end

  defp shift_months(%Date{year: year, month: month}, delta) do
    index = year * 12 + month - 1 + delta
    Date.new!(div(index, 12), rem(index, 12) + 1, 1)
  end

  defp month_start(key), do: Date.from_iso8601!(key <> "-01")

  defp in_range?(%DateTime{} = at, from), do: Date.compare(DateTime.to_date(at), from) != :lt

  defp in_month?(%DateTime{} = at, key), do: Calendar.strftime(at, "%Y-%m") == key
end
