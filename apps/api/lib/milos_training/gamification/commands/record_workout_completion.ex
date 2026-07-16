defmodule MilosTraining.Gamification.Commands.RecordWorkoutCompletion do
  alias MilosTraining.Gamification.Domain.{
    AchievementRules,
    ChallengeProgress,
    DayStreakCalculator,
    MotivationCalculator,
    PerseveranceCalculator,
    PRDetector,
    StreakCalculator
  }

  alias MilosTraining.Gamification.GamificationStore

  def call(%{
        execution:
          %{id: execution_id, user_id: user_id, completed_at_utc: completed_at} = execution,
        completed_executions: completed_executions,
        workout_lookup: workout_lookup,
        account: account,
        settings: settings
      }) do
    current_execution = Enum.find(completed_executions, &(&1.id == execution_id)) || execution
    previous_scores = previous_scores(completed_executions, execution_id, workout_lookup)

    current_scores =
      enrich_scores(
        current_execution.section_scores || [],
        workout_lookup[current_execution.master_workout_id]
      )

    pr_scores = PRDetector.detect(current_scores, previous_scores)
    existing_stats = GamificationStore.get_user_stats(user_id) || %{longest_streak: 0}
    completed_dates = Enum.map(completed_executions, &DateTime.to_date(&1.completed_at_utc))
    prefs = GamificationStore.get_user_preferences(user_id) || %{}
    off_days = Map.get(prefs, :off_days, [])
    today = Date.utc_today()

    streaks =
      StreakCalculator.update(existing_stats,
        completed_dates: completed_dates,
        current_date: today,
        anchor_date: signup_anchor_date(account, completed_dates),
        target: settings.weekly_workout_target,
        shield_reset_day: settings.streak_shield_reset_day
      )

    day_streaks = DayStreakCalculator.calculate(completed_dates, off_days, today)

    motivation_score =
      MotivationCalculator.calculate(completed_dates, settings.weekly_workout_target, today)

    perseverance_score =
      PerseveranceCalculator.calculate(
        Map.get(current_execution, :exercise_modifications, []),
        off_days,
        today
      )

    advancement_count = existing_stats[:advancement_count] || 0

    type_counts = workout_type_counts(completed_executions, workout_lookup)
    current_type = get_workout_type(current_execution, workout_lookup)
    total_prev = max(0, length(completed_executions) - 1)
    prev_type_count = max(0, Map.get(type_counts, current_type, 0) - 1)

    completion_facts = %{
      workout_type: current_type,
      pr_count: length(pr_scores),
      scale_level_slug: current_execution.scale_level_slug,
      consistency_score: streaks.consistency_score,
      prev_type_count: prev_type_count,
      total_prev_completions: total_prev,
      team_workout_count_fn: fn challenge ->
        team_workout_count_for_challenge(challenge, completed_executions, workout_lookup)
      end
    }

    extra_scores = %{
      motivation_score: motivation_score,
      perseverance_score: perseverance_score,
      advancement_count: advancement_count,
      day_streaks: day_streaks
    }

    GamificationStore.transaction(fn ->
      with {:ok, _pr_events} <- persist_pr_events(user_id, execution_id, pr_scores, completed_at),
           total_prs <- GamificationStore.count_achievements_by_prefix(user_id, "pr_event:"),
           stats <-
             build_stats(
               user_id,
               streaks,
               completed_executions,
               total_prs,
               execution,
               extra_scores
             ),
           {:ok, _stats} <- GamificationStore.upsert_user_stats(stats),
           {:ok, _badges} <-
             persist_achievements(
               AchievementRules.milestone_badges(stats, type_counts),
               user_id,
               completed_at
             ),
           {:ok, challenge_result} <-
             persist_challenge_progress(
               user_id,
               current_execution,
               completion_facts,
               completed_at
             ) do
        {:ok,
         %{
           challenge_completions: challenge_result.completions,
           challenge_increments: challenge_result.increments
         }}
      end
    end)
  end

  defp build_stats(user_id, streaks, completed_executions, total_prs, current_execution, extra) do
    %{
      user_id: user_id,
      current_streak: extra.day_streaks.current_streak,
      longest_streak: extra.day_streaks.longest_streak,
      total_workouts: length(completed_executions),
      total_prs: total_prs,
      current_streak_shields: streaks.current_streak_shields,
      last_workout_at: List.last(completed_executions, current_execution).completed_at_utc,
      consistency_score: streaks.consistency_score,
      motivation_score: extra.motivation_score,
      perseverance_score: extra.perseverance_score,
      advancement_count: extra.advancement_count,
      updated_at: DateTime.utc_now()
    }
  end

  defp persist_pr_events(user_id, execution_id, pr_scores, completed_at) do
    pr_scores
    |> Enum.map(&"pr_event:#{execution_id}:#{&1.section_id}")
    |> persist_achievements(user_id, completed_at)
  end

  defp persist_achievements(badge_keys, user_id, completed_at) do
    Enum.reduce_while(badge_keys, {:ok, []}, fn badge_key, {:ok, acc} ->
      case GamificationStore.create_achievement(%{
             user_id: user_id,
             badge_key: badge_key,
             earned_at: completed_at
           }) do
        {:ok, achievement} -> {:cont, {:ok, [achievement | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, achievements} -> {:ok, Enum.reverse(achievements)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp persist_challenge_progress(user_id, _execution, completion_facts, completed_at) do
    completion_date = DateTime.to_date(completed_at)

    GamificationStore.list_active_challenges(completion_date)
    |> Enum.reduce_while({:ok, %{completions: [], increments: []}}, fn challenge, {:ok, acc} ->
      with :ok <- GamificationStore.lock_challenge(challenge.id) do
        current_progress =
          GamificationStore.get_user_challenge_progress(user_id, challenge.id) ||
            %{progress: 0, completed_at: nil, last_increment_event: nil}

        update =
          ChallengeProgress.advance(challenge, current_progress.progress || 0, completion_facts)

        opted_in = GamificationStore.challenge_leaderboard_opted_in?(user_id, challenge.id)

        next_progress =
          if opted_in, do: update.progress, else: min(update.progress, update.target)

        next_completed_at =
          if is_nil(current_progress.completed_at) and update.completed?,
            do: completed_at,
            else: current_progress.completed_at

        last_increment_event =
          if update.increment > 0 do
            %{
              "total_points" => update.increment,
              "events" => Enum.map(update.events, &%{"points" => &1.points, "label" => &1.label})
            }
          else
            current_progress[:last_increment_event]
          end

        case GamificationStore.upsert_user_challenge_progress(%{
               user_id: user_id,
               challenge_id: challenge.id,
               progress: next_progress,
               completed_at: next_completed_at,
               last_increment_event: last_increment_event
             }) do
          {:ok, _progress} ->
            new_increment =
              if update.increment > 0,
                do: [
                  %{
                    challenge_id: challenge.id,
                    title: challenge.title,
                    total_points: update.increment,
                    events: update.events
                  }
                ],
                else: []

            maybe_complete_challenge(
              user_id,
              challenge,
              current_progress,
              update.completed?,
              completed_at,
              acc,
              new_increment
            )

          {:error, reason} ->
            {:halt, {:error, reason}}
        end
      else
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp maybe_complete_challenge(
         user_id,
         challenge,
         current_progress,
         true,
         completed_at,
         acc,
         new_increment
       )
       when is_nil(current_progress.completed_at) do
    case GamificationStore.create_achievement(%{
           user_id: user_id,
           badge_key: challenge.badge_key,
           earned_at: completed_at
         }) do
      {:ok, _achievement} ->
        completion = %{
          user_id: user_id,
          challenge_id: challenge.id,
          title: challenge.title,
          badge_label: challenge.badge_label,
          badge_key: challenge.badge_key
        }

        {:cont,
         {:ok,
          %{
            completions: acc.completions ++ [completion],
            increments: acc.increments ++ new_increment
          }}}

      {:error, reason} ->
        {:halt, {:error, reason}}
    end
  end

  defp maybe_complete_challenge(
         _user_id,
         _challenge,
         _current_progress,
         _completed?,
         _completed_at,
         acc,
         new_increment
       ) do
    {:cont, {:ok, %{completions: acc.completions, increments: acc.increments ++ new_increment}}}
  end

  defp get_workout_type(execution, workout_lookup) do
    case workout_lookup[execution.master_workout_id] do
      %{type: type} when is_binary(type) -> type
      _ -> nil
    end
  end

  defp team_workout_count_for_challenge(challenge, completed_executions, workout_lookup) do
    completed_executions
    |> Enum.filter(fn e ->
      date = DateTime.to_date(e.completed_at_utc)

      Date.compare(date, challenge.starts_at) in [:gt, :eq] and
        Date.compare(date, challenge.ends_at) in [:lt, :eq]
    end)
    |> Enum.count(fn e ->
      case workout_lookup[e.master_workout_id] do
        %{is_team_workout: true} -> true
        _ -> false
      end
    end)
  end

  defp previous_scores(executions, current_execution_id, workout_lookup) do
    executions
    |> Enum.reject(&(&1.id == current_execution_id))
    |> Enum.flat_map(fn execution ->
      enrich_scores(execution.section_scores || [], workout_lookup[execution.master_workout_id])
    end)
  end

  defp enrich_scores(section_scores, nil), do: Enum.map(section_scores, &normalize_score(&1, %{}))

  defp enrich_scores(section_scores, workout) do
    score_configs =
      workout.sections
      |> flatten_sections()
      |> Map.new(fn section -> {section.id, section[:score_config] || %{}} end)

    Enum.map(section_scores, &normalize_score(&1, score_configs))
  end

  defp normalize_score(score, score_configs) do
    section_id = score[:section_id] || score["section_id"]
    config = Map.get(score_configs, section_id, %{})

    %{
      section_id: section_id,
      value: score[:value] || score["value"],
      unit: score[:unit] || score["unit"] || config[:unit] || config["unit"],
      score_type: config[:type] || config["type"] || :reps
    }
  end

  defp flatten_sections(sections) do
    Enum.flat_map(sections, fn section ->
      [section | flatten_sections(Map.get(section, :sections, []))]
    end)
  end

  defp workout_type_counts(executions, workout_lookup) do
    executions
    |> Enum.reduce(%{}, fn execution, acc ->
      case workout_lookup[execution.master_workout_id] do
        %{type: type} when is_binary(type) -> Map.update(acc, type, 1, &(&1 + 1))
        _ -> acc
      end
    end)
  end

  defp signup_anchor_date(%{inserted_at: %DateTime{} = inserted_at}, _completed_dates),
    do: DateTime.to_date(inserted_at)

  defp signup_anchor_date(%{inserted_at: %NaiveDateTime{} = inserted_at}, _completed_dates),
    do: NaiveDateTime.to_date(inserted_at)

  defp signup_anchor_date(_, completed_dates), do: Enum.min(completed_dates)
end
