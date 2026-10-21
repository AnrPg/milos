defmodule Palee.Coaching.RelationshipStore do
  @moduledoc false
  @behaviour Palee.Coaching.Ports.RelationshipStore

  alias Palee.Infrastructure.Tenancy.RepoContext

  defp adapter, do: Application.fetch_env!(:palee, :coaching_relationship_store)

  defp tenant_call(context, function, args) do
    RepoContext.run(context, fn -> apply(adapter(), function, [context | args]) end)
  end

  @impl true
  def start(context, attrs), do: tenant_call(context, :start, [attrs])

  @impl true
  def finish(context, id, ended_by_id), do: tenant_call(context, :finish, [id, ended_by_id])

  @impl true
  def list(context, filters), do: tenant_call(context, :list, [filters])

  @impl true
  def active?(context, coach_id, client_id),
    do: tenant_call(context, :active?, [coach_id, client_id])

  @impl true
  def client_ids(context, coach_id), do: tenant_call(context, :client_ids, [coach_id])
end
