defmodule Palee.Workouts.Queries.MaterializeWorkout do
  @moduledoc """
  Materializes a workout read in the given tenant's scope. Scale levels come
  from the workout's own variations, so they are always its organization's
  set (ADR-128).
  """

  alias Palee.Workouts.Domain.WorkoutMaterializer
  alias Palee.Workouts.Queries.GetWorkout

  @doc "The workout with every scale materialized, or nil."
  def by_id(context, id) do
    case GetWorkout.by_id(context, id) do
      %{} = workout -> %{workout: workout, scales: WorkoutMaterializer.materialize_all(workout)}
      _missing -> nil
    end
  end

  @doc "The workout materialized for one scale, or nil."
  def for_scale(context, id, scale_slug) do
    case GetWorkout.by_id(context, id) do
      %{} = workout -> WorkoutMaterializer.materialize(workout, scale_slug)
      _missing -> nil
    end
  end
end
