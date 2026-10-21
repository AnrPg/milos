defmodule Palee.Gamification.Queries.GetLeaderboard do
  alias Palee.Gamification.GamificationStore

  def call(period, limit \\ 5), do: GamificationStore.get_leaderboard(period, limit)
end
