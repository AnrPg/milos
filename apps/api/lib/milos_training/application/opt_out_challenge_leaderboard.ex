defmodule MilosTraining.Application.OptOutChallengeLeaderboard do
  alias MilosTraining.Gamification

  def call(user_id, challenge_id) do
    Gamification.opt_out_challenge_leaderboard(user_id, challenge_id)
    :ok
  end
end
