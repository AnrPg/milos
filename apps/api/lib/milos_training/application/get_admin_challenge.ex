defmodule MilosTraining.Application.GetAdminChallenge do
  alias MilosTraining.{Gamification, Identity}
  alias MilosTraining.Gamification.Domain.{ChallengeCriteria, ChallengeProgress}

  def call(id) do
    with challenge when not is_nil(challenge) <- Gamification.get_challenge(id) do
      progress_rows =
        Gamification.list_challenge_progress(id)
        |> Map.new(&{&1.user_id, &1})

      users = tracked_users()

      participants =
        users
        |> Enum.map(&normalize_participant(&1, progress_rows, challenge))
        |> Enum.sort_by(fn participant ->
          {
            participant.completed_at == nil,
            -participant.progress,
            participant.nickname
          }
        end)

      {:ok,
       %{
         challenge:
           Map.put(challenge, :progress_summary, progress_summary(participants, challenge)),
         participants: participants
       }}
    else
      nil -> {:error, :not_found}
    end
  end

  defp tracked_users do
    Identity.list_all_users()
  end

  defp normalize_participant(user, progress_rows, challenge) do
    progress_row = Map.get(progress_rows, user.id, %{})
    target = ChallengeProgress.target(challenge)
    progress = Map.get(progress_row, :progress, 0)
    completed_at = Map.get(progress_row, :completed_at)
    updated_at = Map.get(progress_row, :updated_at)

    {completions_done, completions_remaining} =
      if challenge.criteria_type in ["custom", :custom] do
        inc = effective_increment(challenge)
        done = if inc > 0, do: div(progress, inc), else: 0
        remaining = if inc > 0, do: max(0, ceil((target - progress) / inc)), else: 0
        {done, remaining}
      else
        {nil, nil}
      end

    %{
      user_id: user.id,
      nickname: user.nickname,
      role: to_string(user.role),
      progress: progress,
      target: target,
      completion_ratio: completion_ratio(progress, target),
      completed_at: completed_at,
      updated_at: updated_at,
      completions_done: completions_done,
      completions_remaining: completions_remaining
    }
  end

  defp effective_increment(challenge) do
    if ChallengeCriteria.has_rules?(challenge.criteria_value) do
      rules = ChallengeCriteria.rules(challenge.criteria_value)
      Enum.reduce(rules, 0, fn r, acc -> acc + (r["points"] || 0) end)
    else
      ChallengeCriteria.increment_per_completion(challenge)
    end
  end

  defp progress_summary(participants, challenge) do
    target = ChallengeProgress.target(challenge)
    participant_count = length(participants)
    completed_count = Enum.count(participants, & &1.completed_at)
    average_progress = average_progress(participants)

    %{
      participants: participant_count,
      completed: completed_count,
      average_progress: average_progress,
      completion_rate: completion_ratio(completed_count, participant_count),
      target: target
    }
  end

  defp average_progress([]), do: 0.0

  defp average_progress(participants) do
    participants
    |> Enum.reduce(0, fn participant, acc -> acc + participant.progress end)
    |> Kernel./(length(participants))
    |> Float.round(2)
  end

  defp completion_ratio(_value, 0), do: 0.0
  defp completion_ratio(value, total), do: Float.round(value / total, 2)
end
