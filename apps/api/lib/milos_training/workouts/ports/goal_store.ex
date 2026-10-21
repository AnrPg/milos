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

  @type resolved :: %{goals: goals() | nil, inherited_from: Ecto.UUID.t() | nil}

  @callback get_goals(workout_id :: Ecto.UUID.t()) :: goals() | nil

  @doc """
  The goals a workout uses: its own, else the nearest ancestor's along
  `source_workout_id` (class variants and copies, ADR-163), naming that
  ancestor in `inherited_from`.
  """
  @callback resolve_goals(workout_id :: Ecto.UUID.t()) :: resolved()
  @callback put_goals(workout_id :: Ecto.UUID.t(), attrs :: map()) ::
              {:ok, goals()} | {:error, Ecto.Changeset.t()}
end
