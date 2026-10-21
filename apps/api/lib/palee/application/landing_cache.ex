defmodule Palee.Application.LandingCache do
  @behaviour Palee.Application.Ports.LandingCache

  @impl true
  def get_or_fetch(context, user_id, fetch), do: impl().get_or_fetch(context, user_id, fetch)

  @impl true
  def batch_invalidate(user_ids), do: impl().batch_invalidate(user_ids)

  defp impl, do: Application.fetch_env!(:palee, :landing_cache)
end
