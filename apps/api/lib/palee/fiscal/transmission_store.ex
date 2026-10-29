defmodule Palee.Fiscal.TransmissionStore do
  @moduledoc false
  @behaviour Palee.Fiscal.Ports.TransmissionStore

  alias Palee.Infrastructure.Tenancy.RepoContext

  defp adapter, do: Application.fetch_env!(:palee, :fiscal_transmission_store)

  defp tenant_call(context, function, args) do
    RepoContext.run(context, fn -> apply(adapter(), function, [context | args]) end)
  end

  @impl true
  def get_connection(context, authority), do: tenant_call(context, :get_connection, [authority])
  @impl true
  def save_connection(context, authority, attrs),
    do: tenant_call(context, :save_connection, [authority, attrs])

  @impl true
  def set_connection_status(context, authority, status, error),
    do: tenant_call(context, :set_connection_status, [authority, status, error])

  @impl true
  def insert_transmission(context, attrs), do: tenant_call(context, :insert_transmission, [attrs])
  @impl true
  def get_transmission(context, id), do: tenant_call(context, :get_transmission, [id])
  @impl true
  def transmissions_for_documents(context, ids),
    do: tenant_call(context, :transmissions_for_documents, [ids])

  @impl true
  def claim(context, which, now, limit), do: tenant_call(context, :claim, [which, now, limit])
  @impl true
  def finish(context, id, changes, attempt),
    do: tenant_call(context, :finish, [id, changes, attempt])

  @impl true
  def update_transmission(context, id, changes),
    do: tenant_call(context, :update_transmission, [id, changes])

  @impl true
  def wake_waiting(context, now), do: tenant_call(context, :wake_waiting, [now])
  @impl true
  def list_transmissions(context, filters),
    do: tenant_call(context, :list_transmissions, [filters])

  @impl true
  def list_attempts(context, id), do: tenant_call(context, :list_attempts, [id])
end
