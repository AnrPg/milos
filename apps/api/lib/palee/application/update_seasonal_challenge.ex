defmodule Palee.Application.UpdateSeasonalChallenge do
  alias Palee.Application.{
    BroadcastUserSync,
    InvalidateLandingPages,
    TenantStaffRecipients
  }

  alias Palee.Gamification

  def call(context, id, params) do
    with {:ok, challenge} <-
           Gamification.with_tenant_context(context, fn ->
             Gamification.update_seasonal_challenge(id, params)
           end) do
      InvalidateLandingPages.for_all_users()
      broadcast_admin_refresh([context, challenge], "challenge_updated", challenge.id)
      {:ok, challenge}
    end
  end

  def call(id, params) do
    with {:ok, challenge} <- Gamification.update_seasonal_challenge(id, params) do
      InvalidateLandingPages.for_all_users()
      broadcast_admin_refresh([challenge], "challenge_updated", challenge.id)
      {:ok, challenge}
    end
  end

  defp broadcast_admin_refresh(sources, reason, challenge_id) do
    admin_ids = TenantStaffRecipients.user_ids(sources)

    BroadcastUserSync.for_users(
      admin_ids,
      ["admin_challenges"],
      reason: reason,
      payload: %{challenge_id: challenge_id}
    )
  end
end
