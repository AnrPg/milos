defmodule Palee.Application.OptInChallengeLeaderboard do
  alias Palee.{Community, Gamification}

  # TD-092: opt-ins are tenant rows, written in the member's tenant scope.
  # ADR-138: entering a challenge joins the gym club's #challenges channel.
  def call(%{organization_id: _} = context, user_id, challenge_id) do
    with {:ok, _opt_in} = result <-
           Gamification.with_tenant_context(context, fn -> call(user_id, challenge_id) end),
         :ok <-
           Community.join_builtin_channel(
             Map.put(context, :user_id, user_id),
             "challenges",
             "auto"
           ) do
      result
    end
  end

  def call(user_id, challenge_id) do
    case Gamification.get_challenge(challenge_id) do
      nil -> {:error, :not_found}
      _challenge -> Gamification.opt_in_challenge_leaderboard(user_id, challenge_id)
    end
  end
end
