defmodule MilosTraining.Inventory.InventoryStore do
  @moduledoc false
  @behaviour MilosTraining.Inventory.Ports.InventoryStore

  alias MilosTraining.Infrastructure.Tenancy.RepoContext

  defp adapter, do: Application.fetch_env!(:milos_training, :inventory_store)

  defp tenant_call(context, function, args) do
    RepoContext.run(context, fn -> apply(adapter(), function, [context | args]) end)
  end

  @impl true
  def list_machines(context, filters), do: tenant_call(context, :list_machines, [filters])
  @impl true
  def get_machine(context, id), do: tenant_call(context, :get_machine, [id])
  @impl true
  def save_machine(context, id, attrs), do: tenant_call(context, :save_machine, [id, attrs])
  @impl true
  def add_machine_event(context, machine_id, attrs),
    do: tenant_call(context, :add_machine_event, [machine_id, attrs])

  @impl true
  def list_machine_events(context, filters),
    do: tenant_call(context, :list_machine_events, [filters])

  @impl true
  def list_supplies(context, filters), do: tenant_call(context, :list_supplies, [filters])
  @impl true
  def get_supply(context, id), do: tenant_call(context, :get_supply, [id])
  @impl true
  def save_supply(context, id, attrs), do: tenant_call(context, :save_supply, [id, attrs])
  @impl true
  def record_movement(context, supply_id, attrs),
    do: tenant_call(context, :record_movement, [supply_id, attrs])

  @impl true
  def list_movements(context, filters), do: tenant_call(context, :list_movements, [filters])

  @impl true
  def add_supply_report(context, supply_id, attrs),
    do: tenant_call(context, :add_supply_report, [supply_id, attrs])

  @impl true
  def list_supply_reports(context, filters),
    do: tenant_call(context, :list_supply_reports, [filters])
end
