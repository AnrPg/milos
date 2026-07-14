defmodule MilosTraining.Gamification.Queries.GetActiveChallenges do
  alias MilosTraining.Gamification.GamificationStore

  def call(date), do: GamificationStore.list_active_challenges(date)
end
