defmodule MilosTraining.Gamification.GamificationStore do
  @behaviour MilosTraining.Gamification.Ports.GamificationStore

  defp adapter do
    Application.get_env(
      :milos_training,
      :gamification_store,
      MilosTraining.Infrastructure.Gamification.EctoGamificationStore
    )
  end

  @impl true
  def get_user_stats(user_id), do: adapter().get_user_stats(user_id)

  @impl true
  def get_settings, do: adapter().get_settings()

  @impl true
  def update_settings(params), do: adapter().update_settings(params)

  @impl true
  def upsert_user_stats(params), do: adapter().upsert_user_stats(params)

  @impl true
  def create_achievement(params), do: adapter().create_achievement(params)

  @impl true
  def list_user_achievements(user_id), do: adapter().list_user_achievements(user_id)

  @impl true
  def count_achievements_by_prefix(user_id, prefix),
    do: adapter().count_achievements_by_prefix(user_id, prefix)

  @impl true
  def create_challenge(params), do: adapter().create_challenge(params)

  @impl true
  def get_challenge(id), do: adapter().get_challenge(id)

  @impl true
  def update_challenge(id, params), do: adapter().update_challenge(id, params)

  @impl true
  def delete_challenge(id), do: adapter().delete_challenge(id)

  @impl true
  def list_challenges, do: adapter().list_challenges()

  @impl true
  def list_active_challenges(date), do: adapter().list_active_challenges(date)

  @impl true
  def get_user_challenge_progress(user_id, challenge_id),
    do: adapter().get_user_challenge_progress(user_id, challenge_id)

  @impl true
  def list_challenge_progress(challenge_id), do: adapter().list_challenge_progress(challenge_id)

  @impl true
  def upsert_user_challenge_progress(params), do: adapter().upsert_user_challenge_progress(params)

  @impl true
  def set_leaderboard_opt_in(user_id, opted_in),
    do: adapter().set_leaderboard_opt_in(user_id, opted_in)

  @impl true
  def leaderboard_opted_in?(user_id), do: adapter().leaderboard_opted_in?(user_id)

  @impl true
  def get_leaderboard(period, limit), do: adapter().get_leaderboard(period, limit)

  @impl true
  def refresh_leaderboard, do: adapter().refresh_leaderboard()

  @impl true
  def transaction(fun), do: adapter().transaction(fun)

  @impl true
  def opt_in_challenge_leaderboard(user_id, challenge_id),
    do: adapter().opt_in_challenge_leaderboard(user_id, challenge_id)

  @impl true
  def opt_out_challenge_leaderboard(user_id, challenge_id),
    do: adapter().opt_out_challenge_leaderboard(user_id, challenge_id)

  @impl true
  def challenge_leaderboard_opted_in?(user_id, challenge_id),
    do: adapter().challenge_leaderboard_opted_in?(user_id, challenge_id)

  @impl true
  def list_challenge_leaderboard_participants(challenge_id),
    do: adapter().list_challenge_leaderboard_participants(challenge_id)
end
