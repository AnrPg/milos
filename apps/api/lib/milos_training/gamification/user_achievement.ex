defmodule MilosTraining.Gamification.UserAchievement do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "user_achievements" do
    field :badge_key, :string
    field :earned_at, :utc_datetime_usec
    field :user_id, :binary_id
  end

  def changeset(user_achievement \\ %__MODULE__{}, params) do
    user_achievement
    |> cast(params, [:user_id, :badge_key, :earned_at])
    |> validate_required([:user_id, :badge_key, :earned_at])
    |> unique_constraint([:user_id, :badge_key])
    |> foreign_key_constraint(:user_id)
  end
end
