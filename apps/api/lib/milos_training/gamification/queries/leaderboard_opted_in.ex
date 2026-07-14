defmodule MilosTraining.Gamification.Queries.LeaderboardOptedIn do
  alias MilosTraining.Gamification.GamificationStore

  def call(user_id), do: GamificationStore.leaderboard_opted_in?(user_id)
end
