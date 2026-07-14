defmodule MilosTraining.Application.SetLeaderboardPreference do
  alias MilosTraining.Application.GetLeaderboardSnippet
  alias MilosTraining.Application.InvalidateLandingPages
  alias MilosTraining.Gamification

  def call(user, params) do
    with {:ok, opted_in} <- extract_opt_in(params),
         {:ok, %{opted_in: persisted_opted_in}} <-
           Gamification.set_leaderboard_opt_in(user.id, opted_in) do
      build_response(user, persisted_opted_in)
    end
  end

  defp extract_opt_in(%{opted_in: opted_in}) when is_boolean(opted_in), do: {:ok, opted_in}
  defp extract_opt_in(%{"opted_in" => opted_in}) when is_boolean(opted_in), do: {:ok, opted_in}
  defp extract_opt_in(%{body: body}) when is_map(body), do: extract_opt_in(body)
  defp extract_opt_in(%{"body" => body}) when is_map(body), do: extract_opt_in(body)
  defp extract_opt_in(_params), do: {:error, :bad_request}

  defp build_response(user, persisted_opted_in) do
    _ = Gamification.refresh_leaderboard()
    InvalidateLandingPages.for_all_users()

    leaderboard = GetLeaderboardSnippet.call(user)

    {:ok,
     %{
       opted_in: persisted_opted_in,
       visible: leaderboard.visible,
       weekly: leaderboard.weekly,
       monthly: leaderboard.monthly
     }}
  end
end
