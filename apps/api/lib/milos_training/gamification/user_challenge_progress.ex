defmodule MilosTraining.Gamification.UserChallengeProgress do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "user_challenge_progress" do
    field :user_id, :binary_id
    field :challenge_id, :binary_id
    field :progress, :integer, default: 0
    field :completed_at, :utc_datetime_usec
    field :last_increment_event, :map, default: nil

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(progress \\ %__MODULE__{}, params) do
    progress
    |> cast(params, [:user_id, :challenge_id, :progress, :completed_at, :last_increment_event])
    |> validate_required([:user_id, :challenge_id, :progress])
    |> validate_number(:progress, greater_than_or_equal_to: 0)
    |> unique_constraint([:user_id, :challenge_id])
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:challenge_id)
  end
end
