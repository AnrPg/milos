defmodule Palee.Application.CorporateInvoicing do
  @moduledoc """
  Corporate invoicing runs (ADR-098): issues each auto-invoicing client's due
  invoice, marks unpaid invoices overdue and reminds billing contacts, and
  (re)sends a single invoice on an admin's request. Emails go out after the
  database work, never inside a transaction.
  """

  require Logger

  alias Palee.{Finance, Localization, Mailer, Organizations}
  alias Palee.Finance.Emails.CorporateInvoiceEmail

  @doc "The daily run for one organization; returns what it did."
  def run(%{organization: organization, settings: settings}, %Date{} = today) do
    context = %{organization_id: organization.id}
    sender = sender(organization, settings)

    issued = Finance.issue_due_corporate_invoices(context, today)
    Enum.each(issued, &deliver(:issued, &1, &1.client, sender))

    overdue = Finance.mark_overdue_corporate_invoices(context, today)
    interval = Map.get(Finance.get_finance_settings(context), :payment_reminder_interval_days, 7)

    reminded =
      context
      |> Finance.corporate_invoices_needing_reminder(today, interval)
      |> Enum.filter(fn invoice ->
        with {:ok, _sent} <- deliver(:reminder, invoice, invoice.client, sender),
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
         {:ok, _sent} <- deliver(kind, invoice, client, sender) do
      {:ok, invoice}
    end
  end

  defp sendable(_invoice, %{billing_email: email}) when email in [nil, ""],
    do: {:error, :corporate_billing_email_missing}

  defp sendable(%{status: status}, _client) when status in ["issued", "overdue"], do: :ok
  defp sendable(_invoice, _client), do: {:error, :corporate_invoice_closed}

  defp deliver(_kind, _invoice, %{billing_email: email}, _sender) when email in [nil, ""],
    do: {:error, :corporate_billing_email_missing}

  defp deliver(_kind, _invoice, _client, %{live: {:error, _reason} = gated}), do: gated

  defp deliver(kind, invoice, client, sender) do
    localize = fn message, bindings ->
      Localization.translate(sender.locale, message, bindings, "corporate_invoices")
    end

    kind
    |> CorporateInvoiceEmail.build(
      %{invoice: invoice, client: client, gym_name: sender.gym_name, from: sender.from},
      localize
    )
    |> safe_deliver()
  end

  defp sender(organization, settings) do
    from_config = Application.fetch_env!(:palee, :mail_from)

    %{
      gym_name: (settings && settings.brand_name) || organization.name,
      locale: (settings && settings.default_locale) || "en",
      from: {Keyword.fetch!(from_config, :name), Keyword.fetch!(from_config, :address)},
      # ADR-184: a business in demo mode emails nobody.
      live: Organizations.go_live(organization, :send_outside)
    }
  end

  # TD-092: read in the organization's scope (unscoped it was always nil under
  # the production runtime role, so emails fell back to the raw name in English).
  defp settings(organization_id), do: Organizations.get_organization_settings(organization_id)

  # A mail provider outage must not crash the run or the request (see
  # SendOwnerInvitationEmail): Swoosh exits rather than returning an error.
  defp safe_deliver(email) do
    Mailer.deliver(email)
  catch
    :exit, reason ->
      Logger.error("Palee.Mailer.deliver/1 exited: #{inspect(reason)}")
      {:error, :mail_delivery_unavailable}
  end
end
