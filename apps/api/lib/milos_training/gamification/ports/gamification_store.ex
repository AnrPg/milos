defmodule MilosTraining.Gamification.Ports.GamificationStore do
  @callback get_user_stats(Ecto.UUID.t()) :: map() | nil
  @callback get_settings() :: map()
  @callback update_settings(map()) :: {:ok, map()} | {:error, Ecto.Changeset.t()}
  @callback upsert_user_stats(map()) :: {:ok, map()} | {:error, Ecto.Changeset.t()}
  @callback create_achievement(map()) :: {:ok, map()} | {:error, Ecto.Changeset.t()}
  @callback list_user_achievements(Ecto.UUID.t()) :: [map()]
  @callback count_achievements_by_prefix(Ecto.UUID.t(), String.t()) :: non_neg_integer()
  @callback create_challenge(map()) :: {:ok, map()} | {:error, Ecto.Changeset.t()}
  @callback get_challenge(Ecto.UUID.t()) :: map() | nil
  @callback update_challenge(Ecto.UUID.t(), map()) ::
              {:ok, map()} | {:error, Ecto.Changeset.t()} | {:error, :not_found}
  @callback delete_challenge(Ecto.UUID.t()) :: :ok | {:error, :not_found}
  @callback list_challenges() :: [map()]
  @callback list_active_challenges(Date.t()) :: [map()]
  @callback get_user_challenge_progress(Ecto.UUID.t(), Ecto.UUID.t()) :: map() | nil
  @callback list_challenge_progress(Ecto.UUID.t()) :: [map()]
  @callback upsert_user_challenge_progress(map()) :: {:ok, map()} | {:error, Ecto.Changeset.t()}
  @callback set_leaderboard_opt_in(Ecto.UUID.t(), boolean()) ::
              {:ok, boolean()} | {:error, Ecto.Changeset.t() | term()}
  @callback leaderboard_opted_in?(Ecto.UUID.t()) :: boolean()
  @callback get_leaderboard(String.t(), non_neg_integer()) :: [map()]
  @callback refresh_leaderboard() :: :ok | {:error, term()}
  @callback transaction((-> {:ok, term()} | {:error, term()})) :: {:ok, term()} | {:error, term()}
  @callback opt_in_challenge_leaderboard(user_id :: Ecto.UUID.t(), challenge_id :: Ecto.UUID.t()) ::
              {:ok, any()} | {:error, any()}
  @callback opt_out_challenge_leaderboard(user_id :: Ecto.UUID.t(), challenge_id :: Ecto.UUID.t()) ::
              :ok
  @callback challenge_leaderboard_opted_in?(
              user_id :: Ecto.UUID.t(),
              challenge_id :: Ecto.UUID.t()
            ) :: boolean()
  @callback list_challenge_leaderboard_participants(challenge_id :: Ecto.UUID.t()) :: [map()]
end
