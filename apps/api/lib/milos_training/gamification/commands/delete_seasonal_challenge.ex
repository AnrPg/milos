defmodule MilosTraining.Gamification.Commands.DeleteSeasonalChallenge do
  alias MilosTraining.Gamification.GamificationStore

  def call(id) do
    GamificationStore.delete_challenge(id)
  end
end
