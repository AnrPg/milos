defmodule Palee.Application.CreateRecurringClassSeries do
  alias Palee.Application.{ClassLocation, ClassSpace, ScheduleRealtime, TrackAnalyticsEvent}
  alias Palee.Scheduling
  alias Palee.Workouts

  def call(context, params) do
    class_type_id = value(params, :class_type_id)
    master_workout_id = value(params, :master_workout_id)

    with {:ok, _workout} <- fetch_workout(context, master_workout_id),
         {:ok, _class_type} <- fetch_class_type(context, class_type_id),
         :ok <- ClassLocation.check(context, params),
         :ok <- ClassSpace.check_series(context, params),
         {:ok, series} <- create_series(context, params) do
      ScheduleRealtime.broadcast("series_created", series)
      TrackAnalyticsEvent.call("class_series_created", context, series)

      {:ok, series}
    end
  end

  def call(_params), do: {:error, :organization_context_required}

  @doc """
  «Ισχύει για» (ADR-186 §8): one series per branch of `location_ids`, created
  together or not at all; without the list, the one series of `call/2`.
  """
  def call_at_branches(context, params) do
    listed? = Map.has_key?(params, :location_ids) or Map.has_key?(params, "location_ids")

    with {:ok, items} <- ClassLocation.targets(context, params) do
      if listed?, do: create_many(context, params, items), else: one(context, hd(items))
    end
  end

  defp one(context, params) do
    with {:ok, series} <- call(context, params), do: {:ok, [series]}
  end

  defp create_many(context, params, items) do
    with {:ok, _workout} <- fetch_workout(context, value(params, :master_workout_id)),
         {:ok, _class_type} <- fetch_class_type(context, value(params, :class_type_id)),
         :ok <- ClassSpace.check_all(context, items, &ClassSpace.check_series/2),
         {:ok, all} <- ClassLocation.create_all(context, items, &create_series(context, &1)) do
      Enum.each(all, fn series ->
        ScheduleRealtime.broadcast("series_created", series)
        TrackAnalyticsEvent.call("class_series_created", context, series)
      end)

      {:ok, all}
    end
  end

  defp create_series(context, params), do: Scheduling.create_class_series(context, params)

  defp fetch_workout(_context, nil), do: {:ok, nil}

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

  defp value(map, key), do: Map.get(map, key) || Map.get(map, Atom.to_string(key))
end
