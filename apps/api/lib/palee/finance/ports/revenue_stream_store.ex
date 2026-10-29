defmodule Palee.Finance.Ports.RevenueStreamStore do
  @moduledoc """
  Finance rows written by a revenue stream other than memberships (ADR-190):
  the shop's invoices, payments and refunds, tagged with their stream and
  source, and the per-stream totals that separate them in reports.
  """

  @type context :: map()
  @type result :: {:ok, map()} | {:error, term()}

  @doc "An issued invoice with its lines (each line names its source row)."
  @callback record_invoice(context(), map()) :: result()

  @doc """
  The payment settling a stream invoice. Idempotent per source: a second
  call for the same source returns the first payment.
  """
  @callback record_payment(context(), map()) :: result()

  @doc """
  ADR-264: a sale paid on the spot, written at once: the issued invoice
  with its lines (`invoice`) and the payment that settles it (`payment`,
  with its `source_type` / `source_id`), in one transaction. Idempotent
  per payment source: a second call returns the first sale with
  `replayed: true`. Answers `%{invoice, payment, replayed}`.
  """
  @callback record_sale(context(), map()) :: result()

  @doc """
  A refund of a stream payment (`membership_payment_id`, `amount_cents`,
  `idempotency_key`); the reversal inherits the payment's stream and source.
  """
  @callback reverse_payment(context(), map()) :: result()

  @doc "Voids an unpaid stream invoice."
  @callback void_invoice(context(), Ecto.UUID.t(), map()) :: result()

  @doc "Sets the legal receipt reference of an invoice (myDATA MARK, register number)."
  @callback set_fiscal_receipt_ref(context(), Ecto.UUID.t(), String.t() | nil) :: result()

  @doc "Paid and refunded rows of a period, `%{payments, reversals}`, per stream and currency."
  @callback stream_rows(context(), Date.t(), Date.t(), map()) :: %{
              payments: [map()],
              reversals: [map()]
            }

  @doc "The stream invoices, payments and reversals of one source (lineage drill-down)."
  @callback lineage(context(), String.t(), Ecto.UUID.t()) :: map()

  @doc "A member's stream invoices with their payments and reversals (transaction history)."
  @callback list_for_user(context(), String.t(), Ecto.UUID.t()) :: [map()]
end
