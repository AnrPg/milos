defmodule MilosTraining.Gamification.GamificationSetting do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @theme_slugs ~w(ember sage steel aurora royal volt noir daybreak paper lagoon sunset)

  schema "gamification_settings" do
    field :weekly_workout_target, :integer, default: 2
    field :streak_shield_reset_day, :integer
    field :leaderboard_enabled, :boolean, default: true
    field :theme_slug, :string, default: "ember"

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(settings \\ %__MODULE__{}, params) do
    settings
    |> cast(params, [
      :weekly_workout_target,
      :streak_shield_reset_day,
      :leaderboard_enabled,
      :theme_slug
    ])
    |> validate_required([:weekly_workout_target, :leaderboard_enabled, :theme_slug])
    |> validate_number(:weekly_workout_target, greater_than: 0)
    |> validate_number(:streak_shield_reset_day,
      greater_than_or_equal_to: 1,
      less_than_or_equal_to: 28
    )
    |> validate_inclusion(:theme_slug, @theme_slugs)
  end
end
