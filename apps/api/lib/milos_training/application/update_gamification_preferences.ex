defmodule MilosTraining.Application.UpdateGamificationPreferences do
  alias MilosTraining.Application.InvalidateLandingPages
  alias MilosTraining.Gamification.GamificationStore

  # Preferences are owner-only under RLS, so the write runs in the caller's
  # user scope (TD-046).
  def call(context, user_id, params),
    do: GamificationStore.with_tenant_context(context, fn -> call(user_id, params) end)

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
