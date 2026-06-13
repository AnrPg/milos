defmodule MilosTraining.Gamification.Domain.ChallengeLeaderboard do
  @doc "Adds :rank to each participant. Ties share the same rank."
  def rank([]), do: []

  def rank(participants) do
    sorted = Enum.sort_by(participants, & &1.progress, :desc)

    {ranked, _} =
      Enum.map_reduce(sorted, {1, nil}, fn participant, {next_rank, prev_progress} ->
        rank = if participant.progress == prev_progress, do: next_rank - 1, else: next_rank
        {Map.put(participant, :rank, rank), {next_rank + 1, participant.progress}}
      end)

    ranked
  end
end
