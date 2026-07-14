defmodule MilosTraining.Gamification.Domain.ChallengeSchedulePolicy do
  def validate_max_active(existing_challenges, starts_at, ends_at, opts \\ []) do
    max_active = Keyword.get(opts, :max_active, 3)

    existing_challenges
    |> overlapping_challenges(starts_at, ends_at)
    |> max_concurrency(starts_at, ends_at)
    |> case do
      concurrency when concurrency >= max_active -> {:error, :active_challenge_limit_reached}
      _concurrency -> :ok
    end
  end

  defp overlapping_challenges(challenges, starts_at, ends_at) do
    Enum.filter(challenges, fn challenge ->
      not (Date.compare(challenge.ends_at, starts_at) == :lt or
             Date.compare(challenge.starts_at, ends_at) == :gt)
    end)
  end

  defp max_concurrency(challenges, starts_at, ends_at) do
    challenges
    |> Enum.flat_map(fn challenge ->
      clipped_start = max_date(challenge.starts_at, starts_at)
      clipped_end = min_date(challenge.ends_at, ends_at)
      [{clipped_start, 1}, {Date.add(clipped_end, 1), -1}]
    end)
    |> Enum.sort_by(fn {date, delta} -> {date, delta} end)
    |> Enum.reduce({0, 0}, fn {_date, delta}, {current, max_seen} ->
      next = current + delta
      {next, max(max_seen, next)}
    end)
    |> elem(1)
  end

  defp max_date(left, right) do
    if Date.compare(left, right) == :lt, do: right, else: left
  end

  defp min_date(left, right) do
    if Date.compare(left, right) == :gt, do: right, else: left
  end
end
