defmodule MilosTraining.Workouts.Ports.WorkoutStore do
  @callback create_workout(binary(), map()) :: {:ok, map()} | {:error, Ecto.Changeset.t()}
  @callback create_draft(binary()) :: {:ok, map()} | {:error, Ecto.Changeset.t()}
  @callback update_draft(binary(), map()) ::
              {:ok, map()} | {:error, Ecto.Changeset.t()} | {:error, :not_found}
  @callback delete_workout(binary()) ::
              :ok | {:error, Ecto.Changeset.t()} | {:error, :not_found}
  @callback publish_workout(binary(), map()) ::
              {:ok, map()} | {:error, Ecto.Changeset.t()} | {:error, :not_found}
  @callback get_workout(binary()) :: map() | nil
  @callback get_workout_for_admin(binary()) :: map() | nil
  @callback assign_workout(map()) :: {:ok, map()} | {:error, Ecto.Changeset.t()}
  @callback update_assigned_workout(binary(), map()) ::
              {:ok, map()} | {:error, Ecto.Changeset.t()} | {:error, :not_found}
  @callback delete_assigned_workout(binary()) ::
              :ok | {:error, Ecto.Changeset.t()} | {:error, :not_found}
  @callback list_assigned_workouts_for_athlete(binary(), Date.t(), Date.t()) :: [map()]
  @callback list_assigned_workouts_for_admin(Date.t(), Date.t()) :: [map()]
  @callback list_workout_change_targets(binary()) :: [map()]
  @callback list_workouts() :: [map()]
  @callback list_scale_levels() :: [map()]
  @callback replace_scale_levels([map()]) :: {:ok, [map()]} | {:error, Ecto.Changeset.t()}
  @callback reject_assignment_for_athlete(binary(), binary()) ::
              {:ok, map()} | {:error, :not_found | :forbidden | :already_rejected}
  @callback reopen_workout(Ecto.UUID.t()) ::
              {:ok, map()} | {:error, :not_found | :not_published}
  @callback get_assigned_workout(Ecto.UUID.t()) :: map() | nil
  @callback duplicate_workout(Ecto.UUID.t(), String.t()) ::
              {:ok, map()} | {:error, :not_found}
  @callback substitute_assignment_workout(Ecto.UUID.t(), Ecto.UUID.t()) ::
              {:ok, map()} | {:error, :not_found}
  @callback get_assignment_with_auth(Ecto.UUID.t(), map()) ::
              {:ok, map()} | {:error, :not_found | :forbidden}
  @callback list_assignment_messages(Ecto.UUID.t()) :: [map()]
  @callback create_assignment_message(map()) :: {:ok, map()} | {:error, Ecto.Changeset.t()}
  @callback update_assignment_date(Ecto.UUID.t(), String.t(), Date.t()) ::
              {:ok, map()} | {:error, :not_found | Ecto.Changeset.t()}
  @callback delete_superseded_drafts(String.t(), String.t()) :: :ok
end
