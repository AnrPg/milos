defmodule Palee.Gamification.Commands.UpdateSettings do
  alias Palee.Gamification.GamificationStore

  def call(params), do: GamificationStore.update_settings(params)
end
