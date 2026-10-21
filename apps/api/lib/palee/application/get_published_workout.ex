defmodule Palee.Application.GetPublishedWorkout do
  alias Palee.Workouts

  def call(context, id) do
    case Workouts.get_workout(context, id) do
      nil -> {:error, :not_found}
      workout -> {:ok, workout}
    end
  end
end
