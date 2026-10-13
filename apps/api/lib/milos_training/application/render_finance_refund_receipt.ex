defmodule MilosTraining.Application.RenderFinanceRefundReceipt do
  @moduledoc """
  Renders a refund receipt as a printable HTML document (ADR-126) in the
  viewer's locale. The page is produced from the immutable snapshot only, so
  the same receipt and locale always render the same bytes.
  """

  alias MilosTraining.Application.GetFinanceRefundReceipt
  alias MilosTraining.Finance.Domain.RefundReceiptDocument
  alias MilosTraining.Localization

  @rtl_locales ["ar", "he"]

  @messages %{
    title: "Refund receipt",
    receipt_number: "Receipt number",
    issued_on: "Issued on",
    issued_by: "Issued by",
    issued_to: "Issued to",
    refund_details: "Refund details",
    refund_type: "Refund type",
    refunded_amount: "Refunded amount",
    reason: "Reason",
    original_payment: "Original payment",
    payment_date: "Payment date",
    payment_method: "Payment method",
    original_amount: "Original amount",
    invoice: "Invoice",
    previously_refunded: "Previously refunded",
    remaining_paid: "Remaining paid amount",
    type_refund: "Refund",
    type_payment_reversal: "Payment reversal",
    immutable_notice:
      "This receipt is an immutable record of an audited payment reversal. Keep it with your payment records.",
    fingerprint: "Document fingerprint (SHA-256)",
    not_provided: "Not provided"
  }

  def call(context, id, viewer, locale) do
    with {:ok, receipt} <- GetFinanceRefundReceipt.call(context, id, viewer) do
      locale = locale || "en"

      html =
        RefundReceiptDocument.render_html(receipt.snapshot, labels(locale),
          lang: locale,
          dir: if(locale in @rtl_locales, do: "rtl", else: "ltr"),
          fingerprint: receipt.snapshot_sha256
        )

      {:ok, %{html: html, receipt_number: receipt.receipt_number}}
    end
  end

  defp labels(locale) do
    Map.new(RefundReceiptDocument.label_keys(), fn key ->
      {key, Localization.translate(locale, Map.fetch!(@messages, key), %{}, "receipts")}
    end)
  end
end
