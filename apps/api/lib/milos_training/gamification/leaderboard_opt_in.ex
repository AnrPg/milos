defmodule MilosTraining.Gamification.LeaderboardOptIn do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "leaderboard_opt_ins" do
    field :user_id, :binary_id
    field :opted_in_at, :utc_datetime_usec
  end

  def changeset(opt_in \\ %__MODULE__{}, params) do
    opt_in
    |> cast(params, [:user_id, :opted_in_at])
    |> validate_required([:user_id, :opted_in_at])
    |> unique_constraint(:user_id)
    |> foreign_key_constraint(:user_id)
  end
end
