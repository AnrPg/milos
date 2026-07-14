defmodule MilosTraining.Gamification.UserStat do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "user_stats" do
    field :current_streak, :integer, default: 0
    field :longest_streak, :integer, default: 0
    field :total_workouts, :integer, default: 0
    field :total_prs, :integer, default: 0
    field :current_streak_shields, :integer, default: 1
    field :last_workout_at, :utc_datetime_usec
    field :consistency_score, :float, default: 0.0
    field :motivation_score, :float, default: 0.0
    field :perseverance_score, :float, default: 0.0
    field :advancement_count, :integer, default: 0
    field :user_id, :binary_id

    timestamps(inserted_at: false, type: :utc_datetime_usec)
  end

  def changeset(user_stat \\ %__MODULE__{}, params) do
    user_stat
    |> cast(params, [
      :user_id,
      :current_streak,
      :longest_streak,
      :total_workouts,
      :total_prs,
      :current_streak_shields,
      :last_workout_at,
      :consistency_score,
      :motivation_score,
      :perseverance_score,
      :advancement_count,
      :updated_at
    ])
    |> validate_required([
      :user_id,
      :current_streak,
      :longest_streak,
      :total_workouts,
      :total_prs,
      :current_streak_shields,
      :consistency_score,
      :updated_at
    ])
    |> validate_number(:current_streak, greater_than_or_equal_to: 0)
    |> validate_number(:longest_streak, greater_than_or_equal_to: 0)
    |> validate_number(:total_workouts, greater_than_or_equal_to: 0)
    |> validate_number(:total_prs, greater_than_or_equal_to: 0)
    |> validate_number(:current_streak_shields, greater_than_or_equal_to: 0)
    |> unique_constraint(:user_id)
    |> foreign_key_constraint(:user_id)
  end
end
