defmodule Palee.Application.CreateScheduledSlot do
  alias Palee.Application.{ClassLocation, ScheduleRealtime, TrackAnalyticsEvent}
  alias Palee.Scheduling
  alias Palee.Workouts

  def call(context, params) do
    master_workout_id =
      Map.get(params, :master_workout_id) || Map.get(params, "master_workout_id")

    class_type_id = Map.get(params, :class_type_id) || Map.get(params, "class_type_id")

    with {:ok, _workout} <- fetch_workout(context, master_workout_id),
         {:ok, _class_type} <- fetch_class_type(context, class_type_id),
         :ok <- ClassLocation.check(context, params),
         {:ok, slot} <- create_slot(context, params) do
      broadcast_slot_created(slot)
      TrackAnalyticsEvent.call("class_slot_created", context, slot)
      {:ok, slot}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  def call(_params), do: {:error, :organization_context_required}

  @doc """
  «Ισχύει για» (ADR-186 §8): one class per branch of `location_ids`, created
  together or not at all; without the list, the one class of `call/2`.
  """
  def call_at_branches(context, params) do
    listed? = Map.has_key?(params, :location_ids) or Map.has_key?(params, "location_ids")

    with {:ok, items} <- ClassLocation.targets(context, params) do
      if listed?, do: create_many(context, params, items), else: one(context, hd(items))
    end
  end

  defp one(context, params) do
    with {:ok, slot} <- call(context, params), do: {:ok, [slot]}
  end

  defp create_many(context, params, items) do
    with {:ok, _workout} <- fetch_workout(context, value(params, :master_workout_id)),
         {:ok, _class_type} <- fetch_class_type(context, value(params, :class_type_id)),
         {:ok, slots} <- ClassLocation.create_all(context, items, &create_slot(context, &1)) do
      Enum.each(slots, fn slot ->
        broadcast_slot_created(slot)
        TrackAnalyticsEvent.call("class_slot_created", context, slot)
      end)

      {:ok, slots}
    end
  end

  defp value(params, key), do: Map.get(params, key) || Map.get(params, Atom.to_string(key))

  defp create_slot(context, params), do: Scheduling.create_slot(context, params)

  # ADR-176: a class may be saved before its WOD exists.
  defp fetch_workout(_context, nil), do: {:ok, nil}
  defp fetch_workout(_context, ""), do: {:ok, nil}

  defp fetch_workout(context, id) do
    case Workouts.get_workout(context, id) do
      nil -> {:error, :workout_not_found}
      workout -> {:ok, workout}
    end
  end

  defp fetch_class_type(context, id) do
    case Scheduling.get_class_type(context, id) do
      nil -> {:error, :class_type_not_found}
      {:error, reason} -> {:error, reason}
      class_type -> {:ok, class_type}
    end
  end

  defp broadcast_slot_created(slot) do
    ScheduleRealtime.broadcast("slot_created", slot)
  end
end
