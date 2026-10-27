defmodule Palee.Application.CorporateInvoicing do
  @moduledoc """
  Corporate invoicing runs (ADR-098): issues each auto-invoicing client's due
  invoice, marks unpaid invoices overdue and reminds billing contacts, and
  (re)sends a single invoice on an admin's request. Emails go through the
  outbox (ADR-203): the daily run's are idempotent per invoice (and per
  reminder day), so a retried run mails nobody twice; an admin's resend is
  a new email each time.
  """

  alias Palee.{Email, Finance, Organizations}

  @doc "The daily run for one organization; returns what it did."
  def run(%{organization: organization, settings: settings}, %Date{} = today) do
    context = %{organization_id: organization.id}
    sender = sender(organization, settings)

    issued = Finance.issue_due_corporate_invoices(context, today)
    Enum.each(issued, &deliver(:issued, &1, &1.client, sender, "issued"))

    overdue = Finance.mark_overdue_corporate_invoices(context, today)
    interval = Map.get(Finance.get_finance_settings(context), :payment_reminder_interval_days, 7)

    reminded =
      context
      |> Finance.corporate_invoices_needing_reminder(today, interval)
      |> Enum.filter(fn invoice ->
        with {:ok, _sent} <-
               deliver(:reminder, invoice, invoice.client, sender, "reminder:#{today}"),
             {:ok, _invoice} <-
               Finance.mark_corporate_invoice_reminded(context, invoice.id, today) do
          true
        else
          _not_sent -> false
        end
      end)

    %{issued: length(issued), overdue: overdue, reminded: length(reminded)}
  end

  @doc "Sends an invoice to its client's billing contact: a reminder when overdue."
  def send_invoice(context, invoice_id) do
    with %{client: %{} = client} = invoice <-
           Finance.get_corporate_invoice(context, invoice_id) || {:error, :not_found},
         :ok <- sendable(invoice, client),
         sender = sender(context.organization, settings(context.organization_id)),
         kind = if(invoice.status == "overdue", do: :reminder, else: :issued),
         {:ok, _sent} <- deliver(kind, invoice, client, sender, nil) do
      {:ok, invoice}
    end
  end

  defp sendable(_invoice, %{billing_email: email}) when email in [nil, ""],
    do: {:error, :corporate_billing_email_missing}

  defp sendable(%{status: status}, _client) when status in ["issued", "overdue"], do: :ok
  defp sendable(_invoice, _client), do: {:error, :corporate_invoice_closed}

  defp deliver(_kind, _invoice, %{billing_email: email}, _sender, _key) when email in [nil, ""],
    do: {:error, :corporate_billing_email_missing}

  defp deliver(_kind, _invoice, _client, %{live: {:error, _reason} = gated}, _key), do: gated

  defp deliver(kind, invoice, client, sender, key) do
    kind
    |> email_kind()
    |> Email.enqueue(
      client.billing_email,
      %{invoice: invoice, client: client, gym_name: sender.gym_name},
      locale: sender.locale,
      organization_id: sender.organization_id,
      idempotency_key: key && "corporate_invoice:#{invoice.id}:#{key}"
    )
    |> case do
      {:error, :not_live} -> {:error, :business_not_activated}
      {:error, :invalid_address} -> {:error, :corporate_billing_email_missing}
      result -> result
    end
  end

  defp email_kind(:issued), do: :corporate_invoice_issued
  defp email_kind(:reminder), do: :corporate_invoice_reminder

  defp sender(organization, settings) do
    %{
      organization_id: organization.id,
      gym_name: (settings && settings.brand_name) || organization.name,
      locale: (settings && settings.default_locale) || "en",
      # ADR-184: a business in demo mode emails nobody.
      live: Organizations.go_live(organization, :send_outside)
    }
  end

  # TD-092: read in the organization's scope (unscoped it was always nil under
  # the production runtime role, so emails fell back to the raw name in English).
  defp settings(organization_id), do: Organizations.get_organization_settings(organization_id)
end
