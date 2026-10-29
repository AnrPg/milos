defmodule Palee.Fiscal.Domain.DocumentLabels do
  @moduledoc """
  The texts printed on a fiscal document (ADR-245), as English gettext
  message ids of the `fiscal_documents` domain. The application layer
  translates them into the document's language; the renderers only ever
  see the translated map. A missing key prints its English text.
  """

  @messages %{
    title_receipt: "Receipt",
    title_invoice: "Invoice",
    title_credit_note: "Credit note",
    gr_11_1: "Retail sales receipt",
    gr_11_2: "Service receipt",
    gr_11_4: "Retail credit note",
    gr_1_1: "Sales invoice",
    gr_2_1: "Service invoice",
    gr_5_1: "Credit invoice",
    number: "Number",
    issue_date: "Date of issue",
    seller: "Seller",
    buyer: "Customer",
    payment_method: "Payment method",
    pm_cash: "Cash",
    pm_card: "Card",
    pm_bank_transfer: "Bank transfer",
    pm_online: "Online payment",
    pm_other: "Other",
    corrects: "Corrects document",
    credit_reason: "Reason for the credit note",
    cr_product_return: "Product returned",
    cr_billing_error: "Billing error",
    cr_subscription_cancelled: "Subscription cancelled",
    cr_other: "Other",
    col_description: "Description",
    col_quantity: "Qty",
    col_unit_price: "Unit price",
    col_discount: "Discount",
    col_tax_rate: "VAT",
    col_amount: "Amount",
    breakdown: "VAT breakdown",
    rate: "Rate",
    net: "Net",
    tax: "VAT",
    gross: "Gross",
    total_net: "Total excluding VAT",
    total_tax: "Total VAT",
    total_gross: "Total",
    sales_tax: "Sales tax",
    total_sales_tax: "Total sales tax",
    subtotal: "Subtotal",
    prices_include_tax: "Prices include VAT.",
    exempt: "Exempt",
    zero_rated: "Zero-rated",
    tax_id_gr: "Tax ID (AFM)",
    tax_office_gr: "Tax office (DOY)",
    tax_number: "Tax number",
    vat_number: "VAT number",
    siren: "SIREN/SIRET",
    registration_number: "Trade register number",
    ein: "EIN",
    enterprise_number: "Enterprise number",
    uid: "UID",
    email: "Email",
    phone: "Phone",
    mydata_title: "myDATA (AADE)",
    mydata_mark: "MARK",
    mydata_uid: "UID (myDATA)",
    mydata_auth: "Authentication code",
    mydata_pending: "Reporting to myDATA (AADE) is pending.",
    bank_details: "Bank details",
    iban: "IBAN",
    fr_operation: "Category of operation: provision of services",
    fr_late_payment:
      "Late payment: penalties at three times the legal interest rate and a fixed recovery fee of 40 euros (Commercial Code, art. L441-10 and D441-5). No discount for early payment.",
    footer_journal:
      "This document is recorded in the inalterable fiscal journal of the business.",
    fingerprint: "Document fingerprint (SHA-256)",
    page: "Page"
  }

  @doc "`%{key => English message id}`."
  def messages, do: @messages

  def keys, do: Map.keys(@messages)

  @doc "The label of `key`, falling back to its English text."
  def get(labels, key), do: Map.get(labels, key) || Map.fetch!(@messages, key)
end
