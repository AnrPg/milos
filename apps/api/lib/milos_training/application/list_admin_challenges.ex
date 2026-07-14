defmodule MilosTraining.Application.ListAdminChallenges do
  alias MilosTraining.Gamification
  alias MilosTraining.Gamification.Domain.ChallengeProgress

  def call do
    challenges =
      Gamification.list_challenges()
      |> Enum.map(fn challenge ->
        progress = Gamification.list_challenge_progress(challenge.id)

        Map.put(challenge, :progress_summary, %{
          participants: length(progress),
          completed: Enum.count(progress, & &1.completed_at),
          average_progress: average_progress(progress),
          completion_rate: completion_rate(progress),
          target: ChallengeProgress.target(challenge)
        })
      end)

    {:ok, challenges}
  end

  defp average_progress([]), do: 0.0

  defp average_progress(progress) do
    total = Enum.reduce(progress, 0, fn row, acc -> acc + row.progress end)
    Float.round(total / length(progress), 2)
  end

  defp completion_rate([]), do: 0.0

  defp completion_rate(progress) do
    completed = Enum.count(progress, & &1.completed_at)
    Float.round(completed / length(progress), 2)
  end
end
