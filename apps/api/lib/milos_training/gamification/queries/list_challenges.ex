defmodule MilosTraining.Gamification.Queries.ListChallenges do
  alias MilosTraining.Gamification.GamificationStore

  def call, do: GamificationStore.list_challenges()
end
