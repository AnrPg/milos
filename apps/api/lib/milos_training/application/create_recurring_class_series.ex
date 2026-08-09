defmodule MilosTraining.Application.CreateRecurringClassSeries do
  alias MilosTraining.Application.ScheduleRealtime
  alias MilosTraining.Scheduling
  alias MilosTraining.Workouts

  def call(context, params) do
    class_type_id = value(params, :class_type_id)
    master_workout_id = value(params, :master_workout_id)

    with {:ok, _workout} <- fetch_workout(context, master_workout_id),
         {:ok, _class_type} <- fetch_class_type(context, class_type_id),
         {:ok, series} <- create_series(context, params) do
      ScheduleRealtime.broadcast("series_created", series)

      {:ok, series}
    end
  end

  def call(_params), do: {:error, :organization_context_required}

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
