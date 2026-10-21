defmodule Palee.Gamification.Queries.GetActiveChallenges do
  alias Palee.Gamification.GamificationStore

  def call(date), do: GamificationStore.list_active_challenges(date)
end
