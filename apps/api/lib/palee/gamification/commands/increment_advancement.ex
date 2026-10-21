defmodule Palee.Gamification.Commands.IncrementAdvancement do
  alias Palee.Gamification.GamificationStore

  def call(user_id, occurred_at) do
    GamificationStore.increment_advancement(user_id, occurred_at)
  end
end
