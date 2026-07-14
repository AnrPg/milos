defmodule MilosTraining.Gamification.Commands.UpdateSettings do
  alias MilosTraining.Gamification.GamificationStore

  def call(params), do: GamificationStore.update_settings(params)
end
