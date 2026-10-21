defmodule Palee.Gamification.Queries.ListChallenges do
  alias Palee.Gamification.GamificationStore

  def call, do: GamificationStore.list_challenges()
end
