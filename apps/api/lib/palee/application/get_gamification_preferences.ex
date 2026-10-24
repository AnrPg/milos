defmodule Palee.Application.GetGamificationPreferences do
  alias Palee.Gamification.GamificationStore

  # Preferences are owner-only under RLS, so the read runs in the caller's
  # user scope (TD-046).
  def call(context, user_id),
    do: GamificationStore.with_tenant_context(context, fn -> call(user_id) end)

  def call(user_id) do
    {:ok, GamificationStore.get_user_preferences(user_id)}
  end

  @doc "A member without stored preferences (ADR-196 opt-ins included)."
  def defaults, do: %{off_days: [], pr_celebrations: false, challenge_rankings: true}
end
