defmodule Palee.Coaching.CoachingStore do
  @behaviour Palee.Coaching.Ports.CoachingStore

  alias Palee.Infrastructure.Tenancy.RepoContext

  defp adapter do
    Application.fetch_env!(:palee, :coaching_store)
  end

  def with_tenant_context(context, fun) when is_function(fun, 0),
    do: RepoContext.run(context, fun)

  @impl true
  def get_aggregates, do: adapter().get_aggregates()

  @impl true
  def refresh_aggregates, do: adapter().refresh_aggregates()
end
