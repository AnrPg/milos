defmodule MilosTraining.Workouts.Ports.GoalStore do
  @moduledoc """
  Persistence port for WOD goals (ADR-163). Runs inside the tenant session
  the facade opens; row security keeps every read and write in that gym.
  """

  @type goals :: %{
          workout_id: Ecto.UUID.t(),
          muscles: [%{id: String.t(), role: String.t()}],
          qualities: [String.t()],
          stimulus: String.t() | nil,
          visible_to_members: boolean(),
          source: String.t(),
          taxonomy_version: pos_integer(),
          updated_by_id: Ecto.UUID.t() | nil,
          updated_at: DateTime.t()
        }

  @callback get_goals(workout_id :: Ecto.UUID.t()) :: goals() | nil
  @callback put_goals(workout_id :: Ecto.UUID.t(), attrs :: map()) ::
              {:ok, goals()} | {:error, Ecto.Changeset.t()}
end
