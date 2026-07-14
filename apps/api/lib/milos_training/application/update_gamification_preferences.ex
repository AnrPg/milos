defmodule MilosTraining.Application.UpdateGamificationPreferences do
  alias MilosTraining.Application.InvalidateLandingPages
  alias MilosTraining.Gamification.GamificationStore

  def call(user_id, params) do
    case GamificationStore.upsert_user_preferences(user_id, params) do
      {:ok, prefs} ->
        InvalidateLandingPages.for_users([user_id])
        {:ok, prefs}

      {:error, changeset} ->
        {:error, changeset}
    end
  end
end
