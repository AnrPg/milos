defmodule MilosTraining.Widgets.Domain.WidgetSnapshot do
  @moduledoc """
  What the three home-screen widgets show (ADR-173), from the «Σήμερα» items
  across providers (ADR-162) and the member's water today (ADR-159):

    * `water`: millilitres today, the goal and the glass size, the glasses
      count and the neutral status; nil when the member hid water in
      Ευεξία. `can_add` is false without the health-data consent (the
      widget then opens the app instead of adding a glass);
    * `today`: the first #{3} items of the day, in the card's order;
    * `next_class`: the next booked class that has not finished its
      check-in window (#{15}′ after its start), for the check-in widget.

  Nothing here is compared with anyone; no calories, no weight. Pure.
  """

  @today_items 3
  @after_start_minutes 15

  def build(%{items: items, water: water, consented: consented}, %DateTime{} = now) do
    %{
      water: water(water, consented),
      today: items |> Enum.take(@today_items) |> Enum.map(&item/1),
      next_class: next_class(items, now),
      generated_at: now
    }
  end

  defp water(nil, _consented), do: nil

  defp water(water, consented) do
    water
    |> Map.take([:ml, :goal_ml, :glass_ml, :count, :status])
    |> Map.put(:can_add, consented == true)
  end

  defp item(item) do
    %{
      kind: item.kind,
      title: Map.get(item, :title),
      at: Map.get(item, :at),
      status: Map.get(item, :status),
      box_name: get_in(item, [:source, :name])
    }
  end

  defp next_class(items, now) do
    cutoff = DateTime.add(now, -@after_start_minutes * 60, :second)

    items
    |> Enum.filter(fn item ->
      item.kind == "class" and Map.get(item, :status) == "approved" and
        match?(%DateTime{}, item.at) and DateTime.compare(item.at, cutoff) != :lt
    end)
    |> Enum.min_by(& &1.at, DateTime, fn -> nil end)
    |> case do
      nil -> nil
      class -> item(class)
    end
  end
end
