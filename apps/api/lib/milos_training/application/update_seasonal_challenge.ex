defmodule MilosTraining.Application.UpdateSeasonalChallenge do
  alias MilosTraining.Application.{BroadcastUserSync, InvalidateLandingPages}
  alias MilosTraining.{Gamification, Identity}

  def call(id, params) do
    with {:ok, challenge} <- Gamification.update_seasonal_challenge(id, params) do
      InvalidateLandingPages.for_all_users()
      broadcast_admin_refresh("challenge_updated", challenge.id)
      {:ok, challenge}
    end
  end

  defp broadcast_admin_refresh(reason, challenge_id) do
    admin_ids = Identity.list_by_role(:admin) |> Enum.map(& &1.id)

    BroadcastUserSync.for_users(
      admin_ids,
      ["admin_challenges"],
      reason: reason,
      payload: %{challenge_id: challenge_id}
    )
  end
end
