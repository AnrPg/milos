defmodule Palee.Places.DiscoveryStore do
  @moduledoc "Facade over the discovery adapter; every call runs in the person's `RepoContext` session (ADR-154)."

  @behaviour Palee.Places.Ports.DiscoveryStore

  alias Palee.Infrastructure.Tenancy.RepoContext

  defp adapter, do: Application.fetch_env!(:palee, :discovery_store)

  defp run(context, function, args),
    do: RepoContext.run(context, fn -> apply(adapter(), function, [context | args]) end)

  @impl true
  def search(context, kind, area, plan, cursor, limit),
    do: run(context, :search, [kind, area, plan, cursor, limit])

  @impl true
  def counts(context, area, plan, radii_m), do: run(context, :counts, [area, plan, radii_m])

  @impl true
  def pins(context, area, plan, limit), do: run(context, :pins, [area, plan, limit])
end
