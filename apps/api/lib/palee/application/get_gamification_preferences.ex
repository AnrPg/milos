defmodule Palee.Application.GetGamificationPreferences do
  alias Palee.Gamification.GamificationStore

  # Preferences are owner-only under RLS, so the read runs in the caller's
  # user scope (TD-046).
  def call(context, user_id),
    do: GamificationStore.with_tenant_context(context, fn -> call(user_id) end)

  def call(user_id) do
    {:ok, GamificationStore.get_user_preferences(user_id)}
  end
end
