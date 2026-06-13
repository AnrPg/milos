defmodule MilosTraining.Application.GetChallengeLeaderboard do
  alias MilosTraining.{Gamification, Identity}
  alias MilosTraining.Gamification.Domain.{ChallengeLeaderboard, ChallengeProgress}

  def call(challenge_id, requesting_user_id) do
    case Gamification.get_challenge(challenge_id) do
      nil ->
        {:error, :not_found}

      challenge ->
        target = ChallengeProgress.target(challenge)
        opted_in_progress = Gamification.list_challenge_leaderboard_participants(challenge_id)

        user_ids = Enum.map(opted_in_progress, & &1.user_id)

        user_lookup =
          user_ids
          |> Identity.list_by_ids()
          |> Map.new(&{&1.id, &1})

        participants =
          opted_in_progress
          |> Enum.map(fn row ->
            user = Map.get(user_lookup, row.user_id, %{})

            %{
              user_id: row.user_id,
              nickname: Map.get(user, :nickname),
              progress: row.progress,
              target: target,
              completed_at: row.completed_at
            }
          end)
          |> ChallengeLeaderboard.rank()

        my_entry = Enum.find(participants, &(&1.user_id == requesting_user_id))

        {:ok,
         %{
           challenge_id: challenge_id,
           participants: Enum.take(participants, 50),
           my_rank: my_entry && my_entry.rank,
           my_progress: my_entry && my_entry.progress
         }}
    end
  end
end
