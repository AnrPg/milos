defmodule MilosTraining.Gamification.Queries.GetSettings do
  alias MilosTraining.Gamification.GamificationStore

  def call, do: GamificationStore.get_settings()
end
