defmodule MilosTraining.Application.GetGamificationPreferences do
  alias MilosTraining.Gamification.GamificationStore

  def call(user_id) do
    {:ok, GamificationStore.get_user_preferences(user_id)}
  end
end
