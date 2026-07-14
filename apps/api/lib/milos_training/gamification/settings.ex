defmodule MilosTraining.Gamification.Settings do
  alias MilosTraining.Gamification.GamificationStore

  def current do
    GamificationStore.get_settings()
  end

  def weekly_workout_target do
    current().weekly_workout_target
  end

  def streak_shield_reset_day do
    current().streak_shield_reset_day
  end

  def leaderboard_enabled? do
    current().leaderboard_enabled
  end

  def leaderboard_visible_for?(%{role: :admin}, _opted_in), do: true
  def leaderboard_visible_for?(_user, opted_in), do: leaderboard_enabled?() and opted_in
end
