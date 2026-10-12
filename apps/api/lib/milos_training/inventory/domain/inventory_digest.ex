defmodule MilosTraining.Inventory.Domain.InventoryDigest do
  @moduledoc """
  The daily inventory summary (ADR-104): open "running low" reports,
  consumables at low, critical or out, machines whose service is due or comes
  within a week, machines not working, and machine notes from the last day.
  Nothing to report gives `nil`, so quiet days send nothing.
  """

  @soon_days 7

  def build(
        %{supplies: supplies, machines: machines, reports: reports, notes: notes},
        %Date{} = today
      ) do
    low = Enum.filter(supplies, &(&1.stock.status in [:low, :critical, :out]))
    active = Enum.reject(machines, &(&1.status == :retired))
    due = Enum.filter(active, & &1.service_due)

    soon =
      Enum.filter(active, fn machine ->
        not machine.service_due and match?(%Date{}, machine.next_service_on) and
          Date.diff(machine.next_service_on, today) <= @soon_days
      end)

    down = Enum.filter(active, &(&1.status in [:needs_attention, :out_of_order]))

    counts = %{
      reported_low: length(reports),
      low_stock: length(low),
      critical_stock: Enum.count(low, &(&1.stock.status in [:critical, :out])),
      service_due: length(due),
      service_soon: length(soon),
      machines_down: length(down),
      machine_notes: length(notes)
    }

    if Enum.all?(Map.values(counts), &(&1 == 0)) do
      nil
    else
      Map.put(counts, :highlights, highlights(reports, low, down, due ++ soon))
    end
  end

  # Up to five names, most urgent first, for the notification text.
  defp highlights(reports, low, down, service) do
    (Enum.map(reports, & &1.supply_name) ++
       (low |> Enum.sort_by(&rank(&1.stock.status)) |> Enum.map(& &1.name)) ++
       Enum.map(down, & &1.name) ++ Enum.map(service, & &1.name))
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.take(5)
  end

  defp rank(:out), do: 0
  defp rank(:critical), do: 1
  defp rank(_low), do: 2
end
