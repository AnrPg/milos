defmodule Palee.Finance.Domain.CorporateInvoicePolicy do
  @moduledoc """
  Rules for invoicing corporate clients (ADR-098): which period is due, due
  dates, payments against the balance, voiding and overdue reminders.
  """

  alias Palee.Finance.Domain.PaymentModelPolicy

  @open_statuses ["issued", "overdue"]

  @doc """
  The period the daily run should invoice: `agreed` billing invoices the
  current period in advance, `used` billing the previous one once it has
  ended. Periods that ended before the client was created are skipped.
  """
  def period_to_invoice(billing_period, seat_billing, %Date{} = client_since, %Date{} = today) do
    {current_start, _end} = PaymentModelPolicy.corporate_period(billing_period, today)

    {period_start, period_end} =
      if seat_billing == "used",
        do: PaymentModelPolicy.corporate_period(billing_period, Date.add(current_start, -1)),
        else: PaymentModelPolicy.corporate_period(billing_period, today)

    if Date.compare(period_end, client_since) == :lt,
      do: :none,
      else: {:ok, {period_start, period_end}}
  end

  def due_on(%Date{} = issued_on, terms_days), do: Date.add(issued_on, terms_days || 0)

  def open?(%{status: status}), do: status in @open_statuses

  def can_record_payment?(invoice, amount_cents, balance_cents) do
    cond do
      not open?(invoice) -> {:error, :corporate_invoice_closed}
      not (is_integer(amount_cents) and amount_cents > 0) -> {:error, :invalid_payment_amount}
      amount_cents > balance_cents -> {:error, :payment_exceeds_balance}
      true -> :ok
    end
  end

  @doc "The status an invoice has once `paid_cents` of it is paid, on `today`."
  def status_after_payments(%{status: "void"}, _paid_cents, _today), do: "void"

  def status_after_payments(invoice, paid_cents, today) do
    cond do
      paid_cents >= invoice.total_cents -> "paid"
      Date.compare(invoice.due_on, today) == :lt -> "overdue"
      true -> "issued"
    end
  end

  def can_void?(invoice, paid_cents) do
    cond do
      not open?(invoice) -> {:error, :corporate_invoice_closed}
      paid_cents > 0 -> {:error, :corporate_invoice_has_payments}
      true -> :ok
    end
  end

  def reminder_due?(%{status: "overdue", last_reminded_on: nil}, _today, _interval), do: true

  def reminder_due?(%{status: "overdue", last_reminded_on: last}, today, interval),
    do: Date.diff(today, last) >= interval

  def reminder_due?(_invoice, _today, _interval), do: false
end
