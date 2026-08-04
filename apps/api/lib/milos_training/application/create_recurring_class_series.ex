defmodule MilosTraining.Application.CreateRecurringClassSeries do
  alias MilosTraining.Application.ScheduleRealtime
  alias MilosTraining.Scheduling

  def call(context, params) do
    class_type_id = value(params, :class_type_id)

    with {:ok, _class_type} <- fetch_class_type(context, class_type_id),
         {:ok, series} <- create_series(context, params) do
      ScheduleRealtime.broadcast("series_created", series)

      {:ok, series}
    end
  end

  def call(params), do: call(nil, params)

  defp create_series(nil, params), do: Scheduling.create_class_series(params)
  defp create_series(context, params), do: Scheduling.create_class_series(context, params)

  defp fetch_class_type(nil, id) do
    case Scheduling.get_class_type(id) do
      nil -> {:error, :class_type_not_found}
      class_type -> {:ok, class_type}
    end
  end

  defp fetch_class_type(context, id) do
    case Scheduling.get_class_type(context, id) do
      nil -> {:error, :class_type_not_found}
      class_type -> {:ok, class_type}
    end
  end

  defp value(map, key), do: Map.get(map, key) || Map.get(map, Atom.to_string(key))
end
