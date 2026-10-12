defmodule MilosTraining.Finance.Ports.FinanceAccountingStore do
  @moduledoc """
  Persistence port for the ADR-126 accounting artifacts that attach to the
  append-only payment/reversal facts: refund receipts, payment-provider
  reconciliation records and accounting-export runs. Every callback runs in
  the caller's tenant session (`RepoContext.run/2`).
  """

  @type receipt :: map()
  @type record :: map()
  @type export_run :: map()

  @callback issue_refund_receipt(Ecto.UUID.t(), map() | nil) ::
              {:ok, receipt() | nil} | {:error, term()}
  @callback list_refund_receipts(map()) :: [receipt()]
  @callback get_refund_receipt(Ecto.UUID.t()) :: receipt() | nil
  @callback get_refund_receipt_for_reversal(Ecto.UUID.t()) :: receipt() | nil

  @callback record_reconciliation_line(map(), Ecto.UUID.t() | nil) ::
              {:ok, record(), :created | :replayed} | {:error, term()}
  @callback list_reconciliation_records(map()) :: [record()]
  @callback get_reconciliation_record(Ecto.UUID.t()) :: record() | nil
  @callback reconciliation_candidate_facts(Ecto.UUID.t()) ::
              {:ok, record(), [map()]} | {:error, term()}
  @callback match_reconciliation_record(Ecto.UUID.t(), :payment | :reversal, Ecto.UUID.t(), map()) ::
              {:ok, record()} | {:error, term()}
  @callback unmatch_reconciliation_record(Ecto.UUID.t(), map()) ::
              {:ok, record()} | {:error, term()}

  @callback create_accounting_export(map()) :: {:ok, export_run()} | {:error, term()}
  @callback update_accounting_export(Ecto.UUID.t(), map()) ::
              {:ok, export_run()} | {:error, term()}
  @callback get_accounting_export(Ecto.UUID.t()) :: export_run() | nil
  @callback list_accounting_exports(map()) :: [export_run()]
  @callback accounting_export_rows(Date.t(), Date.t()) :: %{String.t() => [map()]}
end
