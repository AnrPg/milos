defmodule MilosTraining.Application.CreateSeasonalChallenge do
  alias MilosTraining.Application.{
    BroadcastUserSync,
    InvalidateLandingPages,
    TenantStaffRecipients
  }

  alias MilosTraining.Gamification

  def call(context, admin_id, params) do
    with {:ok, challenge} <-
           Gamification.with_tenant_context(context, fn ->
             Gamification.create_seasonal_challenge(admin_id, params)
           end) do
      InvalidateLandingPages.for_all_users()
      broadcast_admin_refresh([context, challenge], "challenge_created", challenge.id)
      {:ok, challenge}
    end
  end

  def call(admin_id, params) do
    with {:ok, challenge} <- Gamification.create_seasonal_challenge(admin_id, params) do
      InvalidateLandingPages.for_all_users()
      broadcast_admin_refresh([challenge], "challenge_created", challenge.id)
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
