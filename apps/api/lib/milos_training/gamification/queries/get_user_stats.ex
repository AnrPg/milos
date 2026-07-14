defmodule MilosTraining.Gamification.Queries.GetUserStats do
  alias MilosTraining.Gamification.GamificationStore

  def call(user_id), do: GamificationStore.get_user_stats(user_id)
end
