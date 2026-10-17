defmodule MilosTraining.Gamification do
  alias MilosTraining.Gamification.Commands.{
    CreateSeasonalChallenge,
    DeleteSeasonalChallenge,
    IncrementAdvancement,
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
    GetTrainingQuote,
    GetUserStats,
    LeaderboardOptedIn,
    ListChallenges,
    ListUserAchievements
  }

  def with_tenant_context(context, fun) when is_function(fun, 0),
    do: GamificationStore.with_tenant_context(context, fun)

  defdelegate record_workout_completion(execution), to: RecordWorkoutCompletion, as: :call
  defdelegate create_seasonal_challenge(admin_id, params), to: CreateSeasonalChallenge, as: :call
  defdelegate update_seasonal_challenge(id, params), to: UpdateSeasonalChallenge, as: :call
  defdelegate delete_seasonal_challenge(id), to: DeleteSeasonalChallenge, as: :call
  defdelegate set_leaderboard_opt_in(user_id, opted_in), to: SetLeaderboardOptIn, as: :call
  defdelegate get_settings(), to: GetSettings, as: :call

  defdelegate public_theme_slug(organization_slug),
    to: GamificationStore,
    as: :get_public_theme_slug

  defdelegate update_settings(params), to: UpdateSettings, as: :call
  defdelegate get_challenge(id), to: GetChallenge, as: :call
  defdelegate get_user_stats(user_id), to: GetUserStats, as: :call
  defdelegate get_active_challenges(date), to: GetActiveChallenges, as: :call
  defdelegate get_leaderboard(period, limit), to: GetLeaderboard, as: :call
  defdelegate list_challenges(), to: ListChallenges, as: :call
  defdelegate leaderboard_opted_in?(user_id), to: LeaderboardOptedIn, as: :call

  @doc "Which of these members opted in to leaderboards, in the session's gym."
  def leaderboard_opted_in_user_ids(user_ids),
    do: MilosTraining.Gamification.GamificationStore.leaderboard_opted_in_user_ids(user_ids)

  defdelegate refresh_leaderboard(), to: RefreshLeaderboard, as: :call
  defdelegate get_training_quote(date, subject_id), to: GetTrainingQuote, as: :for_subject
  defdelegate increment_advancement(user_id, occurred_at), to: IncrementAdvancement, as: :call

  defdelegate get_user_preferences(user_id), to: GamificationStore

  defdelegate upsert_user_preferences(user_id, params), to: GamificationStore

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

  # ADR-117 reviewed tenant export/purge. This context owns its table list and
  # retention policy; the shared executor only runs what this policy declares,
  # always inside a RepoContext session for the purge's tenant.
  def tenant_data_policy, do: MilosTraining.Gamification.Domain.TenantDataPolicy.policy()

  def tenant_data_inventory(context),
    do: MilosTraining.TenantData.TableStore.inventory(tenant_data_policy(), context)

  def export_tenant_data(context, mode \\ :full),
    do: MilosTraining.TenantData.TableStore.export(tenant_data_policy(), context, mode)

  def purge_tenant_data(context),
    do: MilosTraining.TenantData.TableStore.purge(tenant_data_policy(), context)
end
