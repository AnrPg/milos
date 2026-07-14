defmodule MilosTraining.Gamification.Commands.SetLeaderboardOptIn do
  alias MilosTraining.Gamification.GamificationStore

  def call(user_id, opted_in) when is_boolean(opted_in) do
    with {:ok, persisted_opt_in} <- GamificationStore.set_leaderboard_opt_in(user_id, opted_in) do
      {:ok, %{opted_in: persisted_opt_in}}
    end
  end

  def call(_user_id, _opted_in), do: {:error, :bad_request}
end
