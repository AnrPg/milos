defmodule Palee.Application.DeleteSeasonalChallenge do
  alias Palee.Application.{
    BroadcastUserSync,
    InvalidateLandingPages,
    TenantStaffRecipients
  }

  alias Palee.Gamification

  def call(context, id) do
    with :ok <-
           Gamification.with_tenant_context(context, fn ->
             Gamification.delete_seasonal_challenge(id)
           end) do
      InvalidateLandingPages.for_all_users()
      broadcast_admin_refresh(context, "challenge_deleted", id)
      :ok
    end
  end

  def call(_id), do: {:error, :organization_context_required}

  defp broadcast_admin_refresh(context, reason, challenge_id) do
    admin_ids = TenantStaffRecipients.user_ids(context)

    BroadcastUserSync.for_users(
      admin_ids,
      ["admin_challenges"],
      reason: reason,
      payload: %{challenge_id: challenge_id}
    )
  end
end
