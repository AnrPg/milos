defmodule MilosTraining.Application.CreateRecurringClassSeries do
  alias MilosTraining.Scheduling

  def call(params) do
    class_type_id = value(params, :class_type_id)

    with {:ok, _class_type} <- fetch_class_type(class_type_id),
         {:ok, series} <- Scheduling.create_class_series(params) do
      Phoenix.PubSub.broadcast(
        MilosTraining.PubSub,
        "schedule:series_created",
        {:schedule_series_created, %{series_id: series.id}}
      )

      {:ok, series}
    end
  end

  defp fetch_class_type(id) do
    case Scheduling.get_class_type(id) do
      nil -> {:error, :class_type_not_found}
      class_type -> {:ok, class_type}
    end
  end

  defp value(map, key), do: Map.get(map, key) || Map.get(map, Atom.to_string(key))
end
