defmodule Palee.Finance.Emails.CorporateInvoiceEmailTest do
  use ExUnit.Case, async: true

  alias Palee.Finance.Emails.CorporateInvoiceEmail
  alias Palee.Localization

  @invoice %{
    invoice_number: "INV-000042-CORP-20261101000000",
    period_start: ~D[2026-11-01],
    period_end: ~D[2026-11-30],
    due_on: ~D[2026-11-15],
    seats_billed: 3,
    unit_price_cents: 2_000,
    total_cents: 6_000,
    paid_cents: 1_000,
    balance_cents: 5_000
  }
  @client %{company_name: "Acme <AE>", contact_name: nil, billing_email: "ap@acme.test"}

  defp build(kind, locale) do
    CorporateInvoiceEmail.build(
      kind,
      %{invoice: @invoice, client: @client, gym_name: "Palee Gym", from: {"Gym", "no@x.test"}},
      &Localization.translate(locale, &1, &2, "corporate_invoices")
    )
  end

  test "an issued invoice email carries the invoice in the gym's language" do
    email = build(:issued, "el")

    assert email.to == [{"", "ap@acme.test"}]
    assert email.subject == "Τιμολόγιο INV-000042-CORP-20261101000000 από Palee Gym"
    assert email.text_body =~ "Υπόλοιπο προς πληρωμή: €50.00"
    assert email.text_body =~ "01/11/2026 – 30/11/2026"
    assert email.html_body =~ "Acme &lt;AE&gt;"
  end

  test "a reminder says the invoice is overdue" do
    email = build(:reminder, "en")
    assert email.subject =~ "Reminder: invoice INV-000042"
    assert email.text_body =~ "was due on 15/11/2026 and is still unpaid"
  end
end
