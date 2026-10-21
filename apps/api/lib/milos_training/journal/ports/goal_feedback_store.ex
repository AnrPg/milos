defmodule MilosTraining.Journal.Ports.GoalFeedbackStore do
  @moduledoc """
  Persistence port for «τι ένιωσες» goal feedback (ADR-163). Runs in the
  member's session: row security admits only their own rows for writes.
  """

  @type entry :: %{
          user_id: Ecto.UUID.t(),
          organization_id: Ecto.UUID.t() | nil,
          master_workout_id: Ecto.UUID.t() | nil,
          voided: boolean()
        }

  @type feedback :: %{
          entry_kind: String.t(),
          entry_id: Ecto.UUID.t(),
          felt_muscles: [String.t()],
          felt_qualities: [String.t()],
          updated_at: DateTime.t()
        }

  @doc "Owner, gym and workout of one entry, whoever may read it, or nil."
  @callback feedback_entry(entry_kind :: String.t(), entry_id :: Ecto.UUID.t()) :: entry() | nil
  @callback get_feedback(String.t(), Ecto.UUID.t(), user_id :: Ecto.UUID.t()) :: feedback() | nil
  @callback put_feedback(attrs :: map()) :: {:ok, feedback()} | {:error, Ecto.Changeset.t()}
end
