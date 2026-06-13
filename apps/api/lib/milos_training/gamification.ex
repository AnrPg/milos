defmodule MilosTraining.Gamification do
  alias MilosTraining.Gamification.Commands.{
    CreateSeasonalChallenge,
    DeleteSeasonalChallenge,
    RecordWorkoutCompletion,
    RefreshLeaderboard,
    SetLeaderboardOptIn,
    UpdateSettings,
    UpdateSeasonalChallenge
  }

  alias MilosTraining.Gamification.Domain.AchievementRules
  alias MilosTraining.Gamification.GamificationStore

  alias MilosTraining.Gamification.Queries.{
    GetActiveChallenges,
    GetChallenge,
    GetLeaderboard,
    GetSettings,
    GetUserStats,
    LeaderboardOptedIn,
    ListChallenges,
    ListUserAchievements
  }

  defdelegate record_workout_completion(execution), to: RecordWorkoutCompletion, as: :call
  defdelegate create_seasonal_challenge(admin_id, params), to: CreateSeasonalChallenge, as: :call
  defdelegate update_seasonal_challenge(id, params), to: UpdateSeasonalChallenge, as: :call
  defdelegate delete_seasonal_challenge(id), to: DeleteSeasonalChallenge, as: :call
  defdelegate set_leaderboard_opt_in(user_id, opted_in), to: SetLeaderboardOptIn, as: :call
  defdelegate get_settings(), to: GetSettings, as: :call
  defdelegate update_settings(params), to: UpdateSettings, as: :call
  defdelegate get_challenge(id), to: GetChallenge, as: :call
  defdelegate get_user_stats(user_id), to: GetUserStats, as: :call
  defdelegate get_active_challenges(date), to: GetActiveChallenges, as: :call
  defdelegate get_leaderboard(period, limit), to: GetLeaderboard, as: :call
  defdelegate list_challenges(), to: ListChallenges, as: :call
  defdelegate leaderboard_opted_in?(user_id), to: LeaderboardOptedIn, as: :call
  defdelegate refresh_leaderboard(), to: RefreshLeaderboard, as: :call

  defdelegate opt_in_challenge_leaderboard(user_id, challenge_id),
    to: GamificationStore

  defdelegate opt_out_challenge_leaderboard(user_id, challenge_id),
    to: GamificationStore

  defdelegate challenge_leaderboard_opted_in?(user_id, challenge_id),
    to: GamificationStore

  defdelegate list_challenge_leaderboard_participants(challenge_id),
    to: GamificationStore

  def challenge_progress(user_id, challenge_id) do
    GamificationStore.get_user_challenge_progress(user_id, challenge_id)
  end

  def list_challenge_progress(challenge_id) do
    GamificationStore.list_challenge_progress(challenge_id)
  end

  def list_visible_achievements(user_id) do
    user_id
    |> ListUserAchievements.call()
    |> Enum.filter(&AchievementRules.visible_badge?(&1.badge_key))
    |> Enum.map(fn achievement ->
      Map.put(achievement, :label, AchievementRules.badge_label(achievement.badge_key))
    end)
  end
end
