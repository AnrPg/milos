defmodule MilosTraining.Workouts.Ports.WorkoutStore do
  @callback create_workout(binary(), map()) :: {:ok, map()} | {:error, Ecto.Changeset.t()}
  @callback create_draft(binary()) :: {:ok, map()} | {:error, Ecto.Changeset.t()}
  @callback update_draft(binary(), map()) ::
              {:ok, map()} | {:error, Ecto.Changeset.t()} | {:error, :not_found}
  @callback publish_workout(binary(), map()) ::
              {:ok, map()} | {:error, Ecto.Changeset.t()} | {:error, :not_found}
  @callback get_workout(binary()) :: map() | nil
  @callback get_workout_for_admin(binary()) :: map() | nil
  @callback list_workouts() :: [map()]
  @callback list_scale_levels() :: [map()]
  @callback replace_scale_levels([map()]) :: {:ok, [map()]} | {:error, Ecto.Changeset.t()}
end
