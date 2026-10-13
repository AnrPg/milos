defmodule MilosTraining.Application.OptOutChallengeLeaderboard do
  alias MilosTraining.Gamification

  # TD-092: opt-ins are tenant rows, removed in the member's tenant scope.
  def call(context, user_id, challenge_id),
    do: Gamification.with_tenant_context(context, fn -> call(user_id, challenge_id) end)

  def call(user_id, challenge_id) do
    Gamification.opt_out_challenge_leaderboard(user_id, challenge_id)
    :ok
  end
end
