defmodule MilosTraining.Workers.RefreshLeaderboardJob do
  use Oban.Worker, queue: :analytics, max_attempts: 3

  alias MilosTraining.Gamification

  @impl Oban.Worker
  def perform(_job) do
    case Gamification.refresh_leaderboard() do
      :ok -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
end
