defmodule MilosTraining.Gamification.ChallengeLeaderboardOptIn do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "challenge_leaderboard_opt_ins" do
    field :user_id, :binary_id
    field :challenge_id, :binary_id
    field :inserted_at, :utc_datetime_usec, autogenerate: {DateTime, :utc_now, []}
  end

  def changeset(opt_in \\ %__MODULE__{}, params) do
    opt_in
    |> cast(params, [:user_id, :challenge_id])
    |> validate_required([:user_id, :challenge_id])
    |> unique_constraint([:user_id, :challenge_id])
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:challenge_id)
  end
end
