defmodule Palee.Finance.Emails.CorporateInvoiceEmail do
  @moduledoc """
  The email a corporate client's billing contact gets when an invoice is
  issued, and while it is overdue (ADR-098). The invoice details are in the
  body; the PDF is downloaded from the admin screen.
  """

  alias Palee.Email.Layout
  alias Palee.Localization

  import Swoosh.Email

  @doc """
  The subject and both bodies, in `locale` (the gym's default locale):
  the invoice strings from the `corporate_invoices` domain, wrapped in the
  shared email layout (ADR-203). `kind` is `:issued` or `:reminder`.
  """
  def render(kind, assigns, locale) when kind in [:issued, :reminder] do
    render(kind, assigns, &Localization.translate(locale, &1, &2, "corporate_invoices"), locale)
  end

  defp render(kind, %{invoice: invoice, client: client, gym_name: gym_name}, localize, locale) do
    bindings = %{
      number: invoice.invoice_number || "",
      gym: gym_name,
      company: client.company_name,
      start: date(invoice.period_start),
      end: date(invoice.period_end),
      due: date(invoice.due_on)
    }

    rows = [
      {localize.("Invoice number", %{}), bindings.number},
      {localize.("Period", %{}), "#{bindings.start} – #{bindings.end}"},
      {localize.("Seats", %{}), Integer.to_string(invoice.seats_billed)},
      {localize.("Price per seat", %{}), money(invoice.unit_price_cents)},
      {localize.("Total", %{}), money(invoice.total_cents)},
      {localize.("Paid", %{}), money(Map.get(invoice, :paid_cents, 0))},
      {localize.("Balance due", %{}),
       money(Map.get(invoice, :balance_cents, invoice.total_cents))},
      {localize.("Due date", %{}), bindings.due}
    ]

    {subject, intro, outro} = copy(kind, bindings, localize)
    greeting = localize.("Hello %{name},", %{name: client.contact_name || client.company_name})
    thanks = localize.("Thank you.", %{})

    reason =
      Layout.t(
        locale,
        "You're receiving this email because you are the billing contact of %{company} at %{business}.",
        %{company: client.company_name, business: gym_name}
      )

    %{
      subject: subject,
      text:
        Layout.text(locale, [greeting, intro, Layout.text_details(rows), outro, thanks, gym_name],
          reason: reason
        ),
      html:
        Layout.html(
          locale,
          [
            Layout.paragraph(greeting),
            Layout.paragraph(intro),
            Layout.details(rows),
            Layout.paragraph(outro),
            Layout.paragraph(thanks),
            Layout.paragraph(gym_name)
          ],
          reason: reason,
          preheader: intro
        )
    }
  end

  @doc """
  The same as a `Swoosh.Email` (the mailer tests use it). `localize`
  translates a message with bindings; `assigns.locale` (default `"en"`)
  picks the layout's language.
  """
  def build(kind, %{client: client, from: from} = assigns, localize)
      when kind in [:issued, :reminder] do
    rendered = render(kind, assigns, localize, Map.get(assigns, :locale, "en"))

    new()
    |> to(client.billing_email)
    |> from(from)
    |> subject(rendered.subject)
    |> text_body(rendered.text)
    |> html_body(rendered.html)
  end

  defp copy(:issued, bindings, localize) do
    {localize.("Invoice %{number} from %{gym}", bindings),
     localize.(
       "%{gym} has issued invoice %{number} to %{company} for the period %{start} – %{end}.",
       bindings
     ), localize.("Please pay by %{due} and quote the invoice number.", bindings)}
  end

  defp copy(:reminder, bindings, localize) do
    {localize.("Reminder: invoice %{number} from %{gym} is overdue", bindings),
     localize.(
       "Invoice %{number} to %{company} was due on %{due} and is still unpaid.",
       bindings
     ), localize.("If you have already paid, please ignore this reminder.", bindings)}
  end

  defp date(%Date{} = date), do: Calendar.strftime(date, "%d/%m/%Y")
  defp date(_other), do: ""

  defp money(cents) when is_integer(cents),
    do: "€" <> :erlang.float_to_binary(cents / 100, decimals: 2)

  defp money(_cents), do: "€0.00"
end
