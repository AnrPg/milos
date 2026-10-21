defmodule Palee.Gamification.Queries.ListUserAchievements do
  alias Palee.Gamification.GamificationStore

  def call(user_id), do: GamificationStore.list_user_achievements(user_id)
end
