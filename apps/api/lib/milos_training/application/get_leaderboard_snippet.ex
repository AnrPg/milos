defmodule MilosTraining.Application.GetLeaderboardSnippet do
  alias MilosTraining.Gamification

  def call(user) do
    settings = Gamification.get_settings()
    opted_in = Gamification.leaderboard_opted_in?(user.id)
    visible = user.role == :admin or (settings.leaderboard_enabled and opted_in)

    %{
      visible: visible,
      opted_in: opted_in,
      weekly: if(visible, do: Gamification.get_leaderboard("weekly", 5), else: []),
      monthly: if(visible, do: Gamification.get_leaderboard("monthly", 5), else: [])
    }
  end
end
