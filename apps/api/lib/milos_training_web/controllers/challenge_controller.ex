defmodule MilosTrainingWeb.ChallengeController do
  use MilosTrainingWeb, :controller

  alias Guardian.Plug, as: GuardianPlug

  alias MilosTraining.Application.{
    GetChallengeLeaderboard,
    OptInChallengeLeaderboard,
    OptOutChallengeLeaderboard
  }

  action_fallback MilosTrainingWeb.FallbackController

  def leaderboard(conn, %{"id" => id}) do
    current_user = GuardianPlug.current_resource(conn)

    with {:ok, payload} <- GetChallengeLeaderboard.call(id, current_user.id) do
      json(conn, payload)
    end
  end

  def opt_in(conn, %{"id" => id}) do
    current_user = GuardianPlug.current_resource(conn)

    with {:ok, _} <- OptInChallengeLeaderboard.call(current_user.id, id) do
      json(conn, %{opted_in: true})
    end
  end

  def opt_out(conn, %{"id" => id}) do
    current_user = GuardianPlug.current_resource(conn)
    :ok = OptOutChallengeLeaderboard.call(current_user.id, id)
    json(conn, %{opted_in: false})
  end
end
