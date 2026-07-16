defmodule MilosTraining.Application.LandingCache do
  @behaviour MilosTraining.Application.Ports.LandingCache

  @impl true
  def get_or_fetch(user_id, fetch), do: impl().get_or_fetch(user_id, fetch)

  @impl true
  def batch_invalidate(user_ids), do: impl().batch_invalidate(user_ids)

  defp impl, do: Application.fetch_env!(:milos_training, :landing_cache)
end
