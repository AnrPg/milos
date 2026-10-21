defmodule Palee.Gamification.Commands.RefreshLeaderboard do
  alias Palee.Gamification.GamificationStore

  def call, do: GamificationStore.refresh_leaderboard()
end
