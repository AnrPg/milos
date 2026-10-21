defmodule Palee.Application.GetMaterializedWorkout do
  alias Palee.Workouts

  def call(context, id) do
    case Workouts.materialize_workout(context, id) do
      nil -> {:error, :not_found}
      payload -> {:ok, payload}
    end
  end
end
