defmodule MilosTraining.Application.CreateSeasonalChallenge do
  alias MilosTraining.Application.{BroadcastUserSync, InvalidateLandingPages}
  alias MilosTraining.{Gamification, Identity}

  def call(admin_id, params) do
    with {:ok, challenge} <- Gamification.create_seasonal_challenge(admin_id, params) do
      InvalidateLandingPages.for_all_users()
      broadcast_admin_refresh("challenge_created", challenge.id)
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
