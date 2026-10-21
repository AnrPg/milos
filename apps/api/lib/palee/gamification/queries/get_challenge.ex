defmodule Palee.Gamification.Queries.GetChallenge do
  alias Palee.Gamification.GamificationStore

  def call(id), do: GamificationStore.get_challenge(id)
end
