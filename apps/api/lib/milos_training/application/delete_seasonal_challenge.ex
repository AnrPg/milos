defmodule MilosTraining.Application.DeleteSeasonalChallenge do
  alias MilosTraining.Application.{BroadcastUserSync, InvalidateLandingPages}
  alias MilosTraining.{Gamification, Identity}

  def call(id) do
    with :ok <- Gamification.delete_seasonal_challenge(id) do
      InvalidateLandingPages.for_all_users()
      broadcast_admin_refresh("challenge_deleted", id)
      :ok
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
