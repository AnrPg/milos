defmodule Palee.Gamification.Queries.GetSettings do
  alias Palee.Gamification.GamificationStore

  def call, do: GamificationStore.get_settings()
end
