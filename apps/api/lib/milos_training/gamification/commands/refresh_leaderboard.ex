defmodule MilosTraining.Gamification.Commands.RefreshLeaderboard do
  alias MilosTraining.Gamification.GamificationStore

  def call, do: GamificationStore.refresh_leaderboard()
end
