defmodule Palee.Journal.GoalFeedback do
  @moduledoc """
  «Τι ένιωσες» (ADR-163): the muscles and qualities a member says they felt
  after one of their own journal entries (an execution or a training-log
  entry). One row per entry and member; it has no rung of its own and is
  read through its entry's rung, like a comment. Values arrive normalised by
  `Anatomy.Domain.GoalSet`.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @entry_kinds ~w(execution training_log)

  schema "goal_feedback" do
    field(:user_id, :binary_id)
    field(:organization_id, :binary_id)
    field(:entry_kind, :string)
    field(:entry_id, :binary_id)
    field(:felt_muscles, {:array, :string}, default: [])
    field(:felt_qualities, {:array, :string}, default: [])

    timestamps(type: :utc_datetime_usec)
  end

  def entry_kinds, do: @entry_kinds

  def changeset(%__MODULE__{} = feedback, attrs) do
    feedback
    |> cast(attrs, [
      :user_id,
      :organization_id,
      :entry_kind,
      :entry_id,
      :felt_muscles,
      :felt_qualities
    ])
    |> validate_required([:user_id, :entry_kind, :entry_id])
    |> validate_inclusion(:entry_kind, @entry_kinds)
    |> unique_constraint([:entry_kind, :entry_id, :user_id])
  end
end
