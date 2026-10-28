defmodule Palee.Application.GetLandingPage do
  alias Palee.Application.{GetLeaderboardSnippet, ListWorkoutExecutions}
  alias Palee.{Finance, Gamification, Messaging, Organizations, Scheduling}
  alias Palee.Gamification.Domain.{ChallengeCriteria, ChallengeProgress, WeeklyGoal}
  alias Palee.Application.LandingCache

  # TD-092: the whole payload is read inside the member's tenant scope. Without
  # it every gamification, execution and messaging read here was empty under
  # the production runtime role (tests only passed on an inherited ambient
  # session scope).
  def call(context, user) do
    cached =
      LandingCache.get_or_fetch(context, user.id, fn ->
        Gamification.with_tenant_context(context, fn -> build_cached_payload(context, user) end)
      end)

    quote = training_quote(user)
    {:ok, Map.put(cached, "quote", quote)}
  end

  def call(_user), do: {:error, :organization_context_required}

  defp build_cached_payload(%{role: role} = context, _user)
       when role in [:owner, :admin, :coach] do
    empty_stats = %{
      "current_streak" => 0,
      "longest_streak" => 0,
      "total_workouts" => 0,
      "total_prs" => 0,
      "current_streak_shields" => 0,
      "consistency_score" => 0.0,
      "motivation_score" => 0.0,
      "perseverance_score" => 0.0,
      "advancement_count" => 0,
      "last_workout_at" => nil
    }

    %{
      "role" => "admin",
      "admin_metrics" => admin_metrics(context),
      "gamification" => %{
        "settings" => Gamification.get_settings(),
        "goal" => nil,
        "stats" => empty_stats,
        "preferences" => nil,
        "badges" => [],
        "active_challenges" => [],
        "leaderboard" => %{
          "visible" => false,
          "opted_in" => false,
          "weekly" => [],
          "monthly" => []
        }
      },
      "coaching_messages" => [],
      "membership" => nil,
      "recent_executions" => []
    }
  end

  defp build_cached_payload(context, user) do
    stats =
      Gamification.get_user_stats(user.id) ||
        %{
          current_streak: 0,
          longest_streak: 0,
          total_workouts: 0,
          total_prs: 0,
          current_streak_shields: 1,
          consistency_score: 0.0,
          motivation_score: 0.0,
          perseverance_score: 100.0,
          advancement_count: 0,
          last_workout_at: nil
        }

    preferences = Gamification.get_user_preferences(user.id) || %{off_days: []}

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
      "role" => to_string(context.role),
      "gamification" => %{
        "settings" => Gamification.get_settings(),
        # ADR-229: the person's own weekly goal (the default until set).
        "goal" => user.id |> Gamification.get_training_goal() |> WeeklyGoal.present(),
        "stats" => stats,
        "preferences" => preferences,
        "badges" => Gamification.list_visible_achievements(user.id),
        "active_challenges" => active_challenges,
        "leaderboard" => GetLeaderboardSnippet.call(user)
      },
      "coaching_messages" => coaching_messages_payload(user),
      "membership" => membership_payload(context, user.id),
      "recent_executions" =>
        executions
        |> Enum.filter(& &1.completed_at_utc)
        |> Enum.sort_by(& &1.completed_at_utc, {:desc, DateTime})
        |> Enum.take(12)
    }
  end

  defp admin_metrics(context) do
    %{
      "member_count" => Organizations.list_active_membership_user_ids(context) |> length(),
      "total_outstanding_cents" => Finance.total_outstanding_balance_cents(context),
      "pending_referral_approvals" => Finance.count_pending_referral_approvals(context),
      "classes_today" => Scheduling.count_classes_today(context)
    }
  end

  defp training_quote(user) do
    Date.utc_today()
    |> Gamification.get_training_quote(user.id)
    |> case do
      nil -> nil
      q -> %{"body" => q.body, "author" => q.author}
    end
  end

  # «Τελευταία από τον coach» (ADR-140 §6): the coaching messages this
  # member received, whatever their role in the gym. A coach's own sent
  # messages are not theirs to read here.
  defp coaching_messages_payload(%{id: user_id}) do
    user_id
    |> Messaging.list_recent_coaching_messages(5)
    |> Enum.reject(&(&1.sender_id == user_id))
    |> Enum.map(fn message ->
      %{
        "id" => message.id,
        "thread_id" => message.thread_id,
        "sender_id" => message.sender_id,
        "body" => message.body,
        "inserted_at" => message.inserted_at
      }
    end)
  end

  defp membership_payload(context, user_id) do
    case Finance.get_member_profile(context, user_id) do
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
