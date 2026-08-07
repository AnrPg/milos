defmodule MilosTraining.Application.GetLeaderboardSnippet do
  alias MilosTraining.Gamification

  @doc """
  Leaderboard visibility for the requesting account.

  Previously an account with the global `:admin` role saw the leaderboard
  regardless of opt-in. That check was removed with F-29: role is a property of
  a membership, and this endpoint carries no tenant context to resolve one
  against, so there is no organization in which the account can be said to be
  an admin here. The bypass was also already inert - `get_leaderboard/2` fails
  closed without an open organization, so it returned empty lists anyway.

  Visibility is therefore the same rule for everyone: the organization has the
  leaderboard enabled, and the member opted in.
  """
  def call(user) do
    settings = Gamification.get_settings()
    opted_in = Gamification.leaderboard_opted_in?(user.id)
    visible = settings.leaderboard_enabled and opted_in

    %{
      visible: visible,
      opted_in: opted_in,
      weekly: if(visible, do: Gamification.get_leaderboard("weekly", 5), else: []),
      monthly: if(visible, do: Gamification.get_leaderboard("monthly", 5), else: [])
    }
  end
end
