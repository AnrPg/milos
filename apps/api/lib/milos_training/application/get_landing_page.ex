defmodule MilosTraining.Application.GetLandingPage do
  alias MilosTraining.Application.{GetLeaderboardSnippet, ListWorkoutExecutions}
  alias MilosTraining.{Coaching, Finance, Gamification}
  alias MilosTraining.Gamification.Domain.{ChallengeCriteria, ChallengeProgress}
  alias MilosTraining.Infrastructure.Cache.LandingCache

  def call(user) do
    payload =
      LandingCache.get_or_fetch(user.id, fn ->
        build_payload(user)
      end)

    {:ok, payload}
  end

  defp build_payload(user) do
    stats =
      Gamification.get_user_stats(user.id) ||
        %{
          current_streak: 0,
          longest_streak: 0,
          total_workouts: 0,
          total_prs: 0,
          current_streak_shields: 1,
          consistency_score: 0.0,
          last_workout_at: nil
        }

    active_challenges =
      Date.utc_today()
      |> Gamification.get_active_challenges()
      |> Enum.map(fn challenge ->
        progress =
          Gamification.challenge_progress(user.id, challenge.id) ||
            %{progress: 0, completed_at: nil, last_increment_event: nil}

        target = ChallengeProgress.target(challenge)
        current_progress = progress.progress || 0
        is_opted_in = Gamification.challenge_leaderboard_opted_in?(user.id, challenge.id)

        completions_remaining =
          cond do
            target <= 0 ->
              0

            current_progress >= target ->
              0

            ChallengeCriteria.has_rules?(challenge.criteria_value) ->
              rules = ChallengeCriteria.rules(challenge.criteria_value)
              max_per = Enum.reduce(rules, 0, fn r, acc -> acc + (r["points"] || 0) end)
              if max_per > 0, do: max(0, ceil((target - current_progress) / max_per)), else: 0

            true ->
              inc = ChallengeCriteria.increment_per_completion(challenge)
              max(0, ceil((target - current_progress) / inc))
          end

        %{
          id: challenge.id,
          title: challenge.title,
          description: challenge.description,
          badge_key: challenge.badge_key,
          badge_label: challenge.badge_label,
          criteria_type: challenge.criteria_type,
          target: target,
          progress: current_progress,
          completed_at: progress.completed_at,
          completed: not is_nil(progress.completed_at),
          starts_at: challenge.starts_at,
          ends_at: challenge.ends_at,
          has_rules: ChallengeCriteria.has_rules?(challenge.criteria_value),
          increment_per_completion:
            unless ChallengeCriteria.has_rules?(challenge.criteria_value) do
              ChallengeCriteria.increment_per_completion(challenge)
            end,
          completions_remaining: completions_remaining,
          is_opted_in: is_opted_in,
          last_progress_event: progress[:last_increment_event]
        }
      end)

    {:ok, executions} = ListWorkoutExecutions.call(user.id)

    %{
      gamification: %{
        settings: Gamification.get_settings(),
        stats: stats,
        badges: Gamification.list_visible_achievements(user.id),
        active_challenges: active_challenges,
        leaderboard: GetLeaderboardSnippet.call(user)
      },
      coach_notes: coach_notes_payload(user),
      membership: membership_payload(user.id),
      recent_executions:
        executions
        |> Enum.filter(& &1.completed_at_utc)
        |> Enum.sort_by(& &1.completed_at_utc, {:desc, DateTime})
        |> Enum.take(12)
    }
  end

  defp coach_notes_payload(%{role: :athlete, id: user_id}) do
    user_id
    |> Coaching.list_notes_for_athlete()
    |> Enum.take(5)
  end

  defp coach_notes_payload(_user), do: []

  defp membership_payload(user_id) do
    case Finance.get_member_profile(user_id) do
      nil ->
        nil

      profile ->
        subscription = profile.active_package_subscription

        last_payment =
          Enum.find(profile.payments, &(&1.payment_status in ["paid", "waived"]))

        %{
          package_name: package_name(subscription),
          package_code: subscription && subscription.package_code_snapshot,
          expiration_date: profile.membership.expires_on,
          last_paid: last_payment && last_payment.paid_on,
          amount: last_payment && last_payment.amount_cents,
          currency: (last_payment && last_payment.currency) || "EUR",
          notes: profile.membership.notes,
          entitlement_status: profile.entitlement.status,
          entitlement_source: profile.entitlement.source
        }
    end
  end

  defp package_name(nil), do: nil

  defp package_name(subscription) do
    case Finance.get_package(subscription.membership_package_id) do
      nil -> subscription.package_code_snapshot
      package -> package.name
    end
  end
end
