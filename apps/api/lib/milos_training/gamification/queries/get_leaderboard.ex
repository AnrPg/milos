defmodule MilosTraining.Gamification.Queries.GetLeaderboard do
  alias MilosTraining.Gamification.GamificationStore

  def call(period, limit \\ 5), do: GamificationStore.get_leaderboard(period, limit)
end
