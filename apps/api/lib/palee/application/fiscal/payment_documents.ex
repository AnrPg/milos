defmodule Palee.Application.Fiscal.PaymentDocuments do
  @moduledoc """
  A recorded payment issues its fiscal document (ADR-262): the money a
  client paid, at the desk or online, gets the legal receipt of the
  business's country in the same use case, so a card payment is always
  tied to its receipt (Greece: ΔΕΔ 1441/2026) and the document reaches the
  tax authority through the outbox (ADR-243).

  * Only once the business's fiscal identity is complete; before that the
    payment keeps Finance's own document only (`:not_configured`).
  * The lines are the invoice's lines with each package's tax category
    (ADR-244). A payment of part of an invoice gets one line per tax group
    of the invoice, in proportion (`SaleLines.payment_part/3`).
  * Idempotent per Finance payment (`finance-payment:<id>`): a retried
    online fulfilment or a replayed desk request returns the same document.
  * A refund or reversal credits that document by the amount given back
    (`credit/5`, idempotent per reversal).
  """

  require Logger

  alias Palee.{Finance, Fiscal, Organizations}
  alias Palee.Fiscal.Domain.SaleLines

  @methods %{
    "cash" => "cash",
    "card_manual" => "card",
    "card" => "card",
    "bank_transfer" => "bank_transfer",
    "online" => "online"
  }

  @doc """
  `{:ok, document}`, `{:ok, :not_configured}` or `{:error, reason}` for a
  Finance `received` result (`ReceiveFinancePayment`).
  """
  def issue(context, received, actor_id, %DateTime{} = now) do
    case Fiscal.identity_status(context) do
      %{complete: true, identity: identity} -> issue(context, identity, received, actor_id, now)
      _incomplete -> {:ok, :not_configured}
    end
  end

  defp issue(context, identity, received, actor_id, now) do
    payment = received.payment
    key = "finance-payment:" <> payment.id

    case Fiscal.document_by_key(context, key) do
      %{} = document -> {:ok, document}
      nil -> issue_new(context, identity, received, key, actor_id, now)
    end
  end

  defp issue_new(context, identity, received, key, actor_id, now) do
    payment = received.payment
    invoice = received.invoice

    with {:ok, sale} <-
           SaleLines.finance_invoice(
             invoice,
             Finance.invoice_lines(context, invoice.id),
             taxes(context),
             identity
           ),
         {:ok, lines} <-
           SaleLines.payment_part(
             sale.lines,
             payment.amount_cents,
             received[:description] || invoice.invoice_number || "Payment"
           ),
         {:ok, document, _mode} <-
           Fiscal.issue(
             context,
             %{
               kind: "receipt",
               issue_date: payment.paid_on,
               currency: sale.currency,
               prices_include_tax: true,
               buyer: nil,
               payment_method: Map.get(@methods, payment.payment_method, "other"),
               lines: lines,
               source_type: "finance_payment",
               source_id: payment.id,
               idempotency_key: key
             },
             actor_id,
             now
           ) do
      {:ok, document}
    else
      {:error, reason} = error ->
        Logger.warning(
          "fiscal_document_not_issued finance_payment_id=#{payment.id} reason=#{inspect(reason)}"
        )

        error
    end
  end

  @doc """
  For money recorded at the desk: the payment stays recorded either way;
  `received` gains `fiscal_document` (a summary or nil) and, when the
  document could not be issued, `fiscal_error`. Repeating the same request
  (same idempotency key) issues it.
  """
  def attach(context, received, actor_id) do
    case issue(context, received, actor_id, DateTime.utc_now()) do
      {:ok, :not_configured} ->
        Map.put(received, :fiscal_document, nil)

      {:ok, document} ->
        Map.put(received, :fiscal_document, summary(document))

      {:error, reason} ->
        Map.merge(received, %{fiscal_document: nil, fiscal_error: code(reason)})
    end
  end

  @doc """
  A reversal (refund or cancelled payment) of a Finance payment credits
  its fiscal document by the amount given back: `{:ok, credit_note}`,
  `{:ok, :no_document}` when the payment issued none, or `{:error, reason}`.
  Idempotent per reversal (`finance-reversal:<id>`).
  """
  def credit(context, payment_id, reversal, actor_id, %DateTime{} = now) do
    case Fiscal.document_by_key(context, "finance-payment:" <> payment_id) do
      nil ->
        {:ok, :no_document}

      document ->
        today = Organizations.local_today(context.organization_id, now)

        case Fiscal.credit(
               context,
               document.id,
               %{amount_cents: reversal.amount_cents},
               today,
               "finance-reversal:" <> reversal.id,
               actor_id,
               now
             ) do
          {:ok, note, _mode} ->
            {:ok, note}

          {:error, reason} = error ->
            Logger.warning(
              "fiscal_credit_not_issued finance_payment_id=#{payment_id} reason=#{inspect(reason)}"
            )

            error
        end
    end
  end

  @doc "Adds `fiscal_credit_note` (or `fiscal_error`) to a desk reversal."
  def attach_credit(context, payment_id, reversal, actor_id) do
    case credit(context, payment_id, reversal, actor_id, DateTime.utc_now()) do
      {:ok, :no_document} ->
        Map.put(reversal, :fiscal_credit_note, nil)

      {:ok, note} ->
        Map.put(reversal, :fiscal_credit_note, summary(note))

      {:error, reason} ->
        Map.merge(reversal, %{fiscal_credit_note: nil, fiscal_error: code(reason)})
    end
  end

  @doc "What a payment's answer shows of its fiscal document."
  def summary(document),
    do: Map.take(document, [:id, :kind, :series, :number, :gross_cents, :currency, :issue_date])

  defp code({reason, _detail}) when is_atom(reason), do: Atom.to_string(reason)
  defp code({reason, _index, _detail}) when is_atom(reason), do: Atom.to_string(reason)
  defp code(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp code(_reason), do: "fiscal_document_failed"

  # Each package's tax category by its code (invoice lines keep the code).
  defp taxes(context) do
    packages =
      context
      |> Finance.list_packages()
      |> Map.new(fn package ->
        {package.code,
         %{
           tax_category: package[:tax_category],
           exemption_reason: package[:exemption_reason]
         }}
      end)

    %{packages: packages}
  end
end
