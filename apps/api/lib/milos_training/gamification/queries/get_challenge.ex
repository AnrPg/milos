defmodule MilosTraining.Gamification.Queries.GetChallenge do
  alias MilosTraining.Gamification.GamificationStore

  def call(id), do: GamificationStore.get_challenge(id)
end
