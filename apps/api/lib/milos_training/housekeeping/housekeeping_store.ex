defmodule MilosTraining.Housekeeping.HousekeepingStore do
  @moduledoc false
  @behaviour MilosTraining.Housekeeping.Ports.HousekeepingStore

  alias MilosTraining.Infrastructure.Tenancy.RepoContext

  defp adapter, do: Application.fetch_env!(:milos_training, :housekeeping_store)

  defp tenant_call(context, function, args) do
    RepoContext.run(context, fn -> apply(adapter(), function, [context | args]) end)
  end

  @impl true
  def list_areas(context, filters), do: tenant_call(context, :list_areas, [filters])
  @impl true
  def get_area(context, id), do: tenant_call(context, :get_area, [id])
  @impl true
  def save_area(context, id, attrs), do: tenant_call(context, :save_area, [id, attrs])
  @impl true
  def start_entry(context, attrs), do: tenant_call(context, :start_entry, [attrs])
  @impl true
  def get_entry(context, id), do: tenant_call(context, :get_entry, [id])
  @impl true
  def finish_entry(context, id, attrs), do: tenant_call(context, :finish_entry, [id, attrs])
  @impl true
  def list_entries(context, filters), do: tenant_call(context, :list_entries, [filters])
end
