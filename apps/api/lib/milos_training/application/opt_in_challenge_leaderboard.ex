defmodule MilosTraining.Application.OptInChallengeLeaderboard do
  alias MilosTraining.Gamification

  # TD-092: opt-ins are tenant rows, written in the member's tenant scope.
  def call(context, user_id, challenge_id),
    do: Gamification.with_tenant_context(context, fn -> call(user_id, challenge_id) end)

  def call(user_id, challenge_id) do
    case Gamification.get_challenge(challenge_id) do
      nil -> {:error, :not_found}
      _challenge -> Gamification.opt_in_challenge_leaderboard(user_id, challenge_id)
    end
  end
end
