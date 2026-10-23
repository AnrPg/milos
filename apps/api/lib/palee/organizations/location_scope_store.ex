defmodule Palee.Organizations.LocationScopeStore do
  @moduledoc """
  Facade over the staff branch scope adapter (ADR-186). Every call runs in
  the gym's `RepoContext` session, so `membership_location_scopes` row
  security applies.
  """

  @behaviour Palee.Organizations.Ports.LocationScopeStore

  alias Palee.Infrastructure.Tenancy.RepoContext

  defp adapter, do: Application.fetch_env!(:palee, :location_scope_store)

  defp tenant_call(context, function, args) do
    RepoContext.run(context, fn -> apply(adapter(), function, [context | args]) end)
  end

  @impl true
  def location_ids(context, membership_id),
    do: tenant_call(context, :location_ids, [membership_id])

  @impl true
  def location_ids_by_membership(_context, []), do: %{}

  def location_ids_by_membership(context, membership_ids),
    do: tenant_call(context, :location_ids_by_membership, [membership_ids])

  @impl true
  def put_scope(context, membership_id, scope),
    do: tenant_call(context, :put_scope, [membership_id, scope])
end
