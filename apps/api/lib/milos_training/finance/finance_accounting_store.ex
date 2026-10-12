defmodule MilosTraining.Finance.FinanceAccountingStore do
  @moduledoc "Tenant-scoped facade over the configured ADR-108 accounting store adapter."

  @behaviour MilosTraining.Finance.Ports.FinanceAccountingStore

  alias MilosTraining.Infrastructure.Tenancy.RepoContext

  defp adapter, do: Application.fetch_env!(:milos_training, :finance_accounting_store)

  def with_tenant_context(context, fun) when is_function(fun, 0),
    do: RepoContext.run(context, fun)

  @impl true
  def issue_refund_receipt(reversal_id, party),
    do: adapter().issue_refund_receipt(reversal_id, party)

  @impl true
  def list_refund_receipts(filters), do: adapter().list_refund_receipts(filters)
  @impl true
  def get_refund_receipt(id), do: adapter().get_refund_receipt(id)

  @impl true
  def get_refund_receipt_for_reversal(reversal_id),
    do: adapter().get_refund_receipt_for_reversal(reversal_id)

  @impl true
  def record_reconciliation_line(line, actor_id),
    do: adapter().record_reconciliation_line(line, actor_id)

  @impl true
  def list_reconciliation_records(filters), do: adapter().list_reconciliation_records(filters)
  @impl true
  def get_reconciliation_record(id), do: adapter().get_reconciliation_record(id)
  @impl true
  def reconciliation_candidate_facts(id), do: adapter().reconciliation_candidate_facts(id)

  @impl true
  def match_reconciliation_record(id, target_kind, target_id, attrs),
    do: adapter().match_reconciliation_record(id, target_kind, target_id, attrs)

  @impl true
  def unmatch_reconciliation_record(id, attrs),
    do: adapter().unmatch_reconciliation_record(id, attrs)

  @impl true
  def create_accounting_export(attrs), do: adapter().create_accounting_export(attrs)
  @impl true
  def update_accounting_export(id, attrs), do: adapter().update_accounting_export(id, attrs)
  @impl true
  def get_accounting_export(id), do: adapter().get_accounting_export(id)
  @impl true
  def list_accounting_exports(filters), do: adapter().list_accounting_exports(filters)

  @impl true
  def accounting_export_rows(range_start, range_end),
    do: adapter().accounting_export_rows(range_start, range_end)
end
