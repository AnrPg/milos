defmodule MilosTraining.Infrastructure.Gamification.EctoGamificationStore do
  @behaviour MilosTraining.Gamification.Ports.GamificationStore

  import Ecto.Query

  alias MilosTraining.Gamification.{
    ChallengeLeaderboardOptIn,
    GamificationSetting,
    LeaderboardOptIn,
    SeasonalChallenge,
    UserAchievement,
    UserChallengeProgress,
    UserStat
  }

  alias MilosTraining.Repo

  @impl true
  def get_user_stats(user_id) do
    case Repo.get_by(UserStat, user_id: user_id) do
      nil -> nil
      stats -> normalize_stats(stats)
    end
  end

  @impl true
  def get_settings do
    case Repo.one(from settings in GamificationSetting, limit: 1) do
      nil ->
        %{
          weekly_workout_target: 2,
          streak_shield_reset_day: nil,
          leaderboard_enabled: true
        }

      settings ->
        normalize_settings(settings)
    end
  end

  @impl true
  def update_settings(params) do
    case Repo.one(from settings in GamificationSetting, limit: 1) do
      nil ->
        %GamificationSetting{}
        |> GamificationSetting.changeset(params)
        |> Repo.insert()
        |> normalize_result(&normalize_settings/1)

      %GamificationSetting{} = settings ->
        settings
        |> GamificationSetting.changeset(params)
        |> Repo.update()
        |> normalize_result(&normalize_settings/1)
    end
  end

  @impl true
  def upsert_user_stats(params) do
    case Repo.get_by(UserStat, user_id: params.user_id) do
      nil ->
        %UserStat{}
        |> UserStat.changeset(params)
        |> Repo.insert()
        |> normalize_result(&normalize_stats/1)

      %UserStat{} = stats ->
        stats
        |> UserStat.changeset(params)
        |> Repo.update()
        |> normalize_result(&normalize_stats/1)
    end
  end

  @impl true
  def create_achievement(params) do
    case Repo.get_by(UserAchievement, user_id: params.user_id, badge_key: params.badge_key) do
      nil ->
        %UserAchievement{}
        |> UserAchievement.changeset(params)
        |> Repo.insert()
        |> normalize_result(&normalize_achievement/1)

      %UserAchievement{} = achievement ->
        {:ok, normalize_achievement(achievement)}
    end
  end

  @impl true
  def list_user_achievements(user_id) do
    UserAchievement
    |> where([achievement], achievement.user_id == ^user_id)
    |> order_by([achievement], desc: achievement.earned_at)
    |> Repo.all()
    |> Enum.map(&normalize_achievement/1)
  end

  @impl true
  def count_achievements_by_prefix(user_id, prefix) do
    UserAchievement
    |> where([achievement], achievement.user_id == ^user_id)
    |> where([achievement], like(achievement.badge_key, ^"#{prefix}%"))
    |> Repo.aggregate(:count)
  end

  @impl true
  def create_challenge(params) do
    %SeasonalChallenge{}
    |> SeasonalChallenge.changeset(params)
    |> Repo.insert()
    |> normalize_result(&normalize_challenge/1)
  end

  @impl true
  def get_challenge(id) do
    case Repo.get(SeasonalChallenge, id) do
      nil -> nil
      %SeasonalChallenge{} = challenge -> normalize_challenge(challenge)
    end
  end

  @impl true
  def update_challenge(id, params) do
    case Repo.get(SeasonalChallenge, id) do
      nil ->
        {:error, :not_found}

      %SeasonalChallenge{} = challenge ->
        challenge
        |> SeasonalChallenge.changeset(params)
        |> Repo.update()
        |> normalize_result(&normalize_challenge/1)
    end
  end

  @impl true
  def delete_challenge(id) do
    case Repo.get(SeasonalChallenge, id) do
      nil ->
        {:error, :not_found}

      %SeasonalChallenge{} = challenge ->
        case Repo.delete(challenge) do
          {:ok, _deleted} -> :ok
          {:error, changeset} -> {:error, changeset}
        end
    end
  end

  @impl true
  def list_challenges do
    SeasonalChallenge
    |> order_by([challenge], desc: challenge.starts_at, desc: challenge.inserted_at)
    |> Repo.all()
    |> Enum.map(&normalize_challenge/1)
  end

  @impl true
  def list_active_challenges(date) do
    SeasonalChallenge
    |> where([challenge], challenge.starts_at <= ^date and challenge.ends_at >= ^date)
    |> order_by([challenge], asc: challenge.starts_at, asc: challenge.inserted_at)
    |> Repo.all()
    |> Enum.map(&normalize_challenge/1)
  end

  @impl true
  def get_user_challenge_progress(user_id, challenge_id) do
    case Repo.get_by(UserChallengeProgress, user_id: user_id, challenge_id: challenge_id) do
      nil -> nil
      progress -> normalize_progress(progress)
    end
  end

  @impl true
  def list_challenge_progress(challenge_id) do
    UserChallengeProgress
    |> where([progress], progress.challenge_id == ^challenge_id)
    |> Repo.all()
    |> Enum.map(&normalize_progress/1)
  end

  @impl true
  def upsert_user_challenge_progress(params) do
    case Repo.get_by(UserChallengeProgress,
           user_id: params.user_id,
           challenge_id: params.challenge_id
         ) do
      nil ->
        %UserChallengeProgress{}
        |> UserChallengeProgress.changeset(params)
        |> Repo.insert()
        |> normalize_result(&normalize_progress/1)

      %UserChallengeProgress{} = progress ->
        progress
        |> UserChallengeProgress.changeset(params)
        |> Repo.update()
        |> normalize_result(&normalize_progress/1)
    end
  end

  @impl true
  def set_leaderboard_opt_in(user_id, true) do
    now = DateTime.utc_now()

    case Repo.get_by(LeaderboardOptIn, user_id: user_id) do
      nil ->
        %LeaderboardOptIn{}
        |> LeaderboardOptIn.changeset(%{user_id: user_id, opted_in_at: now})
        |> Repo.insert()
        |> normalize_opt_in_result(true)

      %LeaderboardOptIn{} = opt_in ->
        opt_in
        |> LeaderboardOptIn.changeset(%{user_id: user_id, opted_in_at: now})
        |> Repo.update()
        |> normalize_opt_in_result(true)
    end
  end

  @impl true
  def set_leaderboard_opt_in(user_id, false) do
    {_deleted, _rows} =
      LeaderboardOptIn
      |> where([opt_in], opt_in.user_id == ^user_id)
      |> Repo.delete_all()

    {:ok, false}
  end

  @impl true
  def leaderboard_opted_in?(user_id) do
    Repo.exists?(from opt_in in LeaderboardOptIn, where: opt_in.user_id == ^user_id)
  end

  @weekly_leaderboard_query """
  SELECT user_id, nickname, workouts_this_week, prs_this_month
  FROM weekly_leaderboard
  ORDER BY workouts_this_week DESC, nickname ASC
  LIMIT $1
  """

  @monthly_leaderboard_query """
  SELECT user_id, nickname, workouts_this_week, prs_this_month
  FROM weekly_leaderboard
  ORDER BY prs_this_month DESC, nickname ASC
  LIMIT $1
  """

  @impl true
  def get_leaderboard(period, limit) do
    query =
      case period do
        "monthly" -> @monthly_leaderboard_query
        _ -> @weekly_leaderboard_query
      end

    case Repo.query(query, [limit]) do
      {:ok, %{rows: rows}} ->
        rows
        |> Enum.with_index(1)
        |> Enum.map(fn {[user_id, nickname, workouts_this_week, prs_this_month], rank} ->
          %{
            rank: rank,
            user_id: normalize_uuid(user_id),
            nickname: nickname,
            workouts_this_week: workouts_this_week,
            prs_this_month: prs_this_month
          }
        end)

      {:error, _reason} ->
        []
    end
  end

  @impl true
  def refresh_leaderboard do
    case Repo.query("REFRESH MATERIALIZED VIEW CONCURRENTLY weekly_leaderboard") do
      {:ok, _result} ->
        :ok

      {:error, %Postgrex.Error{postgres: %{message: message}}} when is_binary(message) ->
        if String.contains?(message, "cannot run inside a transaction block") do
          case Repo.query("REFRESH MATERIALIZED VIEW weekly_leaderboard") do
            {:ok, _result} -> :ok
            {:error, reason} -> {:error, reason}
          end
        else
          {:error, message}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def transaction(fun) when is_function(fun, 0) do
    Repo.transaction(fn ->
      case fun.() do
        {:ok, value} -> value
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
    |> case do
      {:ok, value} -> {:ok, value}
      {:error, reason} -> {:error, reason}
    end
  end

  defp normalize_result({:ok, record}, normalizer), do: {:ok, normalizer.(record)}

  defp normalize_result({:error, %Ecto.Changeset{} = changeset}, _normalizer),
    do: {:error, changeset}

  defp normalize_stats(%UserStat{} = stats) do
    %{
      id: stats.id,
      user_id: stats.user_id,
      current_streak: stats.current_streak,
      longest_streak: stats.longest_streak,
      total_workouts: stats.total_workouts,
      total_prs: stats.total_prs,
      current_streak_shields: stats.current_streak_shields,
      last_workout_at: stats.last_workout_at,
      consistency_score: stats.consistency_score,
      updated_at: stats.updated_at
    }
  end

  defp normalize_achievement(%UserAchievement{} = achievement) do
    %{
      id: achievement.id,
      user_id: achievement.user_id,
      badge_key: achievement.badge_key,
      earned_at: achievement.earned_at
    }
  end

  defp normalize_challenge(%SeasonalChallenge{} = challenge) do
    %{
      id: challenge.id,
      title: challenge.title,
      description: challenge.description,
      criteria_type: to_string(challenge.criteria_type),
      criteria_value: challenge.criteria_value || %{},
      badge_key: challenge.badge_key,
      badge_label: challenge.badge_label,
      starts_at: challenge.starts_at,
      ends_at: challenge.ends_at,
      created_by_id: challenge.created_by_id,
      inserted_at: challenge.inserted_at,
      updated_at: challenge.updated_at
    }
  end

  defp normalize_progress(%UserChallengeProgress{} = progress) do
    %{
      id: progress.id,
      user_id: progress.user_id,
      challenge_id: progress.challenge_id,
      progress: progress.progress,
      completed_at: progress.completed_at,
      last_increment_event: progress.last_increment_event,
      inserted_at: progress.inserted_at,
      updated_at: progress.updated_at
    }
  end

  defp normalize_settings(%GamificationSetting{} = settings) do
    %{
      id: settings.id,
      weekly_workout_target: settings.weekly_workout_target,
      streak_shield_reset_day: settings.streak_shield_reset_day,
      leaderboard_enabled: settings.leaderboard_enabled,
      inserted_at: settings.inserted_at,
      updated_at: settings.updated_at
    }
  end

  defp normalize_opt_in_result({:ok, _record}, opted_in), do: {:ok, opted_in}

  defp normalize_opt_in_result({:error, %Ecto.Changeset{} = changeset}, _opted_in),
    do: {:error, changeset}

  defp normalize_uuid(value) when is_binary(value) do
    case Ecto.UUID.load(value) do
      {:ok, uuid} -> uuid
      :error -> value
    end
  end

  defp normalize_uuid(value), do: value

  @impl true
  def opt_in_challenge_leaderboard(user_id, challenge_id) do
    case Repo.get_by(ChallengeLeaderboardOptIn, user_id: user_id, challenge_id: challenge_id) do
      nil ->
        %ChallengeLeaderboardOptIn{}
        |> ChallengeLeaderboardOptIn.changeset(%{user_id: user_id, challenge_id: challenge_id})
        |> Repo.insert()

      existing ->
        {:ok, existing}
    end
  end

  @impl true
  def opt_out_challenge_leaderboard(user_id, challenge_id) do
    ChallengeLeaderboardOptIn
    |> where([o], o.user_id == ^user_id and o.challenge_id == ^challenge_id)
    |> Repo.delete_all()

    :ok
  end

  @impl true
  def challenge_leaderboard_opted_in?(user_id, challenge_id) do
    ChallengeLeaderboardOptIn
    |> where([o], o.user_id == ^user_id and o.challenge_id == ^challenge_id)
    |> Repo.exists?()
  end

  @impl true
  def list_challenge_leaderboard_participants(challenge_id) do
    UserChallengeProgress
    |> join(:inner, [p], o in ChallengeLeaderboardOptIn,
        on: p.user_id == o.user_id and p.challenge_id == o.challenge_id)
    |> where([p, _o], p.challenge_id == ^challenge_id)
    |> order_by([p, _o], desc: p.progress)
    |> limit(50)
    |> Repo.all()
    |> Enum.map(&normalize_progress/1)
  end
end
