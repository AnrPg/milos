defmodule MilosTraining.Application.OptInChallengeLeaderboard do
  alias MilosTraining.Gamification

  def call(user_id, challenge_id) do
    case Gamification.get_challenge(challenge_id) do
      nil -> {:error, :not_found}
      _challenge -> Gamification.opt_in_challenge_leaderboard(user_id, challenge_id)
    end
  end
end
