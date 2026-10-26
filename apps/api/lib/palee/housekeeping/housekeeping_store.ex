defmodule Palee.Housekeeping.HousekeepingStore do
  @moduledoc false
  @behaviour Palee.Housekeeping.Ports.HousekeepingStore

  alias Palee.Infrastructure.Tenancy.RepoContext

  defp adapter, do: Application.fetch_env!(:palee, :housekeeping_store)

  defp tenant_call(context, function, args) do
    RepoContext.run(context, fn -> apply(adapter(), function, [context | args]) end)
  end

  @impl true
  def last_cleaned(context, area_ids), do: tenant_call(context, :last_cleaned, [area_ids])
  @impl true
  def start_entry(context, attrs), do: tenant_call(context, :start_entry, [attrs])
  @impl true
  def get_entry(context, id), do: tenant_call(context, :get_entry, [id])
  @impl true
  def finish_entry(context, id, attrs), do: tenant_call(context, :finish_entry, [id, attrs])
  @impl true
  def list_entries(context, filters), do: tenant_call(context, :list_entries, [filters])
  @impl true
  def list_schedules(context), do: tenant_call(context, :list_schedules, [])
  @impl true
  def put_schedule(context, space_id, attrs),
    do: tenant_call(context, :put_schedule, [space_id, attrs])

  @impl true
  def delete_schedule(context, space_id), do: tenant_call(context, :delete_schedule, [space_id])
end
