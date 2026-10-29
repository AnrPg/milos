defmodule Palee.Fiscal.FiscalStore do
  @moduledoc false
  @behaviour Palee.Fiscal.Ports.FiscalStore

  alias Palee.Infrastructure.Tenancy.RepoContext

  defp adapter, do: Application.fetch_env!(:palee, :fiscal_store)

  defp tenant_call(context, function, args) do
    RepoContext.run(context, fn -> apply(adapter(), function, [context | args]) end)
  end

  @impl true
  def transaction(context, fun), do: tenant_call(context, :transaction, [fun])

  @impl true
  def get_identity(context), do: tenant_call(context, :get_identity, [])
  @impl true
  def save_identity(context, attrs), do: tenant_call(context, :save_identity, [attrs])

  @impl true
  def lock_journal_head(context), do: tenant_call(context, :lock_journal_head, [])
  @impl true
  def insert_journal_entry(context, entry),
    do: tenant_call(context, :insert_journal_entry, [entry])

  @impl true
  def list_journal_entries(context, opts), do: tenant_call(context, :list_journal_entries, [opts])

  @impl true
  def next_sequence(context, series), do: tenant_call(context, :next_sequence, [series])
  @impl true
  def insert_document(context, document, lines),
    do: tenant_call(context, :insert_document, [document, lines])

  @impl true
  def get_document(context, id, opts), do: tenant_call(context, :get_document, [id, opts])
  @impl true
  def get_document_by_idempotency_key(context, key),
    do: tenant_call(context, :get_document_by_idempotency_key, [key])

  @impl true
  def list_documents(context, filters), do: tenant_call(context, :list_documents, [filters])
  @impl true
  def credited_lines(context, id), do: tenant_call(context, :credited_lines, [id])
  @impl true
  def documents_between(context, from, to),
    do: tenant_call(context, :documents_between, [from, to])

  @impl true
  def first_issue_date(context), do: tenant_call(context, :first_issue_date, [])

  @impl true
  def latest_closings(context), do: tenant_call(context, :latest_closings, [])
  @impl true
  def insert_closing(context, closing), do: tenant_call(context, :insert_closing, [closing])
  @impl true
  def list_closings(context, filters), do: tenant_call(context, :list_closings, [filters])

  @impl true
  def purge(context), do: tenant_call(context, :purge, [])
end
