defmodule Palee.Gamification.Domain.ChallengeSchedulePolicyTest do
  use ExUnit.Case, async: true

  alias Palee.Gamification.Domain.ChallengeSchedulePolicy

  defp challenge(starts_at, ends_at), do: %{starts_at: starts_at, ends_at: ends_at}

  test "a range that crosses a month end still counts every overlap" do
    existing = for _ <- 1..3, do: challenge(~D[2026-10-24], ~D[2026-10-31])

    assert ChallengeSchedulePolicy.validate_max_active(existing, ~D[2026-10-24], ~D[2026-10-31]) ==
             {:error, :active_challenge_limit_reached}
  end

  test "a range that crosses a year end still counts every overlap" do
    existing = [
      challenge(~D[2026-12-28], ~D[2027-01-04]),
      challenge(~D[2026-12-30], ~D[2027-01-02]),
      challenge(~D[2026-12-31], ~D[2027-01-01])
    ]

    assert ChallengeSchedulePolicy.validate_max_active(existing, ~D[2026-12-31], ~D[2027-01-01]) ==
             {:error, :active_challenge_limit_reached}
  end

  test "back-to-back ranges never run at the same time" do
    existing = [
      challenge(~D[2026-10-01], ~D[2026-10-09]),
      challenge(~D[2026-10-10], ~D[2026-10-19]),
      challenge(~D[2026-10-20], ~D[2026-11-02])
    ]

    assert ChallengeSchedulePolicy.validate_max_active(existing, ~D[2026-10-01], ~D[2026-11-02]) ==
             :ok
  end
end
