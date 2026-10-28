defmodule Palee.Gamification.GamificationSetting do
  @moduledoc """
  A box's streak rules (ADR-226): how many streak shields each member gets
  and when they renew, and whether the leaderboard shows. The weekly workout
  goal is each person's own (`Palee.Gamification.Domain.WeeklyGoal`).
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @default_streak_shields 1
  @max_streak_shields 5

  schema "gamification_settings" do
    field :organization_id, :binary_id
    field :streak_shields, :integer, default: @default_streak_shields
    field :streak_shield_reset_day, :integer
    field :leaderboard_enabled, :boolean, default: true

    timestamps(type: :utc_datetime_usec)
  end

  def default_streak_shields, do: @default_streak_shields
  def max_streak_shields, do: @max_streak_shields

  def changeset(settings \\ %__MODULE__{}, params) do
    settings
    |> cast(params, [
      :organization_id,
      :streak_shields,
      :streak_shield_reset_day,
      :leaderboard_enabled
    ])
    |> validate_required([:streak_shields, :leaderboard_enabled])
    |> validate_number(:streak_shields,
      greater_than_or_equal_to: 0,
      less_than_or_equal_to: @max_streak_shields
    )
    |> validate_number(:streak_shield_reset_day,
      greater_than_or_equal_to: 1,
      less_than_or_equal_to: 28
    )
    |> check_constraint(:streak_shields, name: :gamification_settings_streak_shields_check)
  end
end
