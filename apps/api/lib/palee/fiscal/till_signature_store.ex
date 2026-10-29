defmodule Palee.Fiscal.TillSignatureStore do
  @moduledoc false
  @behaviour Palee.Fiscal.Ports.TillSignatureStore

  alias Palee.Infrastructure.Tenancy.RepoContext

  defp adapter, do: Application.fetch_env!(:palee, :fiscal_till_store)

  defp tenant_call(context, function, args) do
    RepoContext.run(context, fn -> apply(adapter(), function, [context | args]) end)
  end

  @impl true
  def get_connection(context, device), do: tenant_call(context, :get_connection, [device])

  @impl true
  def save_connection(context, device, attrs),
    do: tenant_call(context, :save_connection, [device, attrs])

  @impl true
  def set_connection_status(context, device, status, error),
    do: tenant_call(context, :set_connection_status, [device, status, error])

  @impl true
  def update_connection_check(context, device, attrs),
    do: tenant_call(context, :update_connection_check, [device, attrs])

  @impl true
  def insert_signature(context, attrs), do: tenant_call(context, :insert_signature, [attrs])
  @impl true
  def get_signature(context, id), do: tenant_call(context, :get_signature, [id])

  @impl true
  def signatures_for_documents(context, ids),
    do: tenant_call(context, :signatures_for_documents, [ids])

  @impl true
  def claim(context, which, now, limit), do: tenant_call(context, :claim, [which, now, limit])

  @impl true
  def finish(context, id, changes, attempt),
    do: tenant_call(context, :finish, [id, changes, attempt])

  @impl true
  def update_signature(context, id, changes),
    do: tenant_call(context, :update_signature, [id, changes])

  @impl true
  def wake_waiting(context, now), do: tenant_call(context, :wake_waiting, [now])
  @impl true
  def list_signatures(context, filters), do: tenant_call(context, :list_signatures, [filters])
  @impl true
  def list_attempts(context, id), do: tenant_call(context, :list_attempts, [id])
end
