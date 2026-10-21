defmodule Palee.Finance.Emails.CorporateInvoiceEmail do
  @moduledoc """
  The email a corporate client's billing contact gets when an invoice is
  issued, and while it is overdue (ADR-098). The invoice details are in the
  body; the PDF is downloaded from the admin screen.
  """

  import Swoosh.Email

  @doc """
  `localize` translates a message with bindings (the gym's default locale);
  `kind` is `:issued` or `:reminder`.
  """
  def build(kind, %{invoice: invoice, client: client, gym_name: gym_name, from: from}, localize)
      when kind in [:issued, :reminder] do
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

    new()
    |> to(client.billing_email)
    |> from(from)
    |> subject(subject)
    |> text_body(text_body([greeting, intro], rows, [outro, thanks, gym_name]))
    |> html_body(html_body([greeting, intro], rows, [outro, thanks, gym_name]))
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

  defp text_body(intro, rows, outro) do
    table = Enum.map_join(rows, "\n", fn {label, value} -> "#{label}: #{value}" end)
    Enum.join(intro ++ [table] ++ outro, "\n\n") <> "\n"
  end

  defp html_body(intro, rows, outro) do
    paragraphs = &Enum.map_join(&1, "", fn line -> "<p>#{escape(line)}</p>" end)

    table =
      Enum.map_join(rows, "", fn {label, value} ->
        ~s(<tr><td style="padding:4px 12px 4px 0;color:#555;">#{escape(label)}</td>) <>
          ~s(<td style="padding:4px 0;font-weight:600;">#{escape(value)}</td></tr>)
      end)

    """
    <div style="font-family: -apple-system, Segoe UI, sans-serif; max-width: 520px; margin: 0 auto; color: #1a1a1a;">
      #{paragraphs.(intro)}
      <table style="border-collapse: collapse; margin: 16px 0;">#{table}</table>
      #{paragraphs.(outro)}
    </div>
    """
  end

  defp date(%Date{} = date), do: Calendar.strftime(date, "%d/%m/%Y")
  defp date(_other), do: ""

  defp money(cents) when is_integer(cents),
    do: "€" <> :erlang.float_to_binary(cents / 100, decimals: 2)

  defp money(_cents), do: "€0.00"

  defp escape(value) do
    value
    |> to_string()
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
  end
end
