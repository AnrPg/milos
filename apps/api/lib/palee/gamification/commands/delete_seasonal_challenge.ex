defmodule Palee.Gamification.Commands.DeleteSeasonalChallenge do
  alias Palee.Gamification.GamificationStore

  def call(id) do
    GamificationStore.delete_challenge(id)
  end
end
