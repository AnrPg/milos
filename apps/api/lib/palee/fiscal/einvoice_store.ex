defmodule Palee.Fiscal.EInvoiceStore do
  @moduledoc false
  @behaviour Palee.Fiscal.Ports.EInvoiceStore

  alias Palee.Infrastructure.Tenancy.RepoContext

  defp adapter, do: Application.fetch_env!(:palee, :fiscal_einvoice_store)

  defp tenant_call(context, function, args) do
    RepoContext.run(context, fn -> apply(adapter(), function, [context | args]) end)
  end

  @impl true
  def get_connection(context, network), do: tenant_call(context, :get_connection, [network])

  @impl true
  def save_connection(context, network, attrs),
    do: tenant_call(context, :save_connection, [network, attrs])

  @impl true
  def set_connection_status(context, network, status, error),
    do: tenant_call(context, :set_connection_status, [network, status, error])

  @impl true
  def update_connection_check(context, network, attrs),
    do: tenant_call(context, :update_connection_check, [network, attrs])

  @impl true
  def insert_submission(context, attrs), do: tenant_call(context, :insert_submission, [attrs])
  @impl true
  def get_submission(context, id), do: tenant_call(context, :get_submission, [id])

  @impl true
  def submissions_for_documents(context, ids),
    do: tenant_call(context, :submissions_for_documents, [ids])

  @impl true
  def claim(context, which, now, limit), do: tenant_call(context, :claim, [which, now, limit])

  @impl true
  def finish(context, id, changes, attempt),
    do: tenant_call(context, :finish, [id, changes, attempt])

  @impl true
  def update_submission(context, id, changes),
    do: tenant_call(context, :update_submission, [id, changes])

  @impl true
  def wake_waiting(context, now), do: tenant_call(context, :wake_waiting, [now])

  @impl true
  def wake_submitted(context, provider_id, now),
    do: tenant_call(context, :wake_submitted, [provider_id, now])

  @impl true
  def list_submissions(context, filters), do: tenant_call(context, :list_submissions, [filters])
  @impl true
  def list_attempts(context, id), do: tenant_call(context, :list_attempts, [id])
end
