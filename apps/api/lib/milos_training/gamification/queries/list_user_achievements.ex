defmodule MilosTraining.Gamification.Queries.ListUserAchievements do
  alias MilosTraining.Gamification.GamificationStore

  def call(user_id), do: GamificationStore.list_user_achievements(user_id)
end
