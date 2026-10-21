defmodule Palee.Gamification.GamificationSetting do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "gamification_settings" do
    field :organization_id, :binary_id
    field :weekly_workout_target, :integer, default: 2
    field :streak_shield_reset_day, :integer
    field :leaderboard_enabled, :boolean, default: true

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(settings \\ %__MODULE__{}, params) do
    settings
    |> cast(params, [
      :organization_id,
      :weekly_workout_target,
      :streak_shield_reset_day,
      :leaderboard_enabled
    ])
    |> validate_required([:weekly_workout_target, :leaderboard_enabled])
    |> validate_number(:weekly_workout_target, greater_than: 0)
    |> validate_number(:streak_shield_reset_day,
      greater_than_or_equal_to: 1,
      less_than_or_equal_to: 28
    )
  end
end
