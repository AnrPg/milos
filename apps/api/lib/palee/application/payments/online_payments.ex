defmodule Palee.Application.Payments.OnlinePayments do
  @moduledoc """
  ADR-246/247 use cases: staff connect the business's provider account and
  follow and refund payments; members pay an open invoice on the
  provider's page, optionally saving the card for automatic payment of
  later invoices, and manage their saved cards.
  """

  alias Palee.Application.Payments.Webhooks
  alias Palee.Application.PublicURL
  alias Palee.Finance
  alias Palee.Fiscal
  alias Palee.Payments
  alias Palee.Payments.Domain.Consent

  @open_invoice_statuses ~w(issued partially_paid overdue)

  # ── Staff ───────────────────────────────────────────────────────────────

  def account(context) do
    account = Payments.account(context)

    %{
      account:
        account &&
          Map.put(account, :webhook_url, Webhooks.url(context.organization_id, account.id)),
      providers: providers(),
      environments: Payments.environments()
    }
  end

  defp providers do
    if Application.get_env(:palee, :payments_sandbox, false) == true,
      do: Payments.providers(),
      else: Payments.providers() -- ["sandbox"]
  end

  def save_account(context, params) do
    with {:ok, _account} <-
           Payments.save_account(context, params, Map.get(context, :user_id), now()) do
      {:ok, account(context)}
    end
  end

  def list(context, filters), do: Payments.list(context, filters)

  def get(context, id) do
    with {:ok, payment} <- Payments.get(context, id) do
      {:ok, Map.put(payment, :refunds, Payments.refunds(context, id))}
    end
  end

  def refund(context, id, params),
    do: Payments.refund(context, id, params, Map.get(context, :user_id), now())

  def retry(context, id), do: Payments.refresh(context, id, nil, now())

  # ── Member ──────────────────────────────────────────────────────────────

  @doc "What the member is about to pay and the text they agree to when saving the card."
  def checkout_terms(context, invoice_id, language) do
    with {:ok, invoice} <- member_invoice(context, invoice_id) do
      terms = consent_terms(context, invoice, language)

      {:ok,
       %{
         available: Payments.available?(context),
         amount_cents: invoice.balance_due_cents,
         currency: invoice.currency,
         consent_text: Consent.text(language(language), terms),
         consent_version: Consent.version()
       }}
    end
  end

  @doc "Opens a checkout for the member's open invoice; the app sends them to `redirect_url`."
  def pay_invoice(context, invoice_id, params) do
    language = language(params[:language])

    with {:ok, invoice} <- member_invoice(context, invoice_id) do
      save? = params[:save_card] == true
      base = PublicURL.base_url() |> String.trim_trailing("/")

      Payments.start_checkout(
        context,
        %{
          purpose_type: "finance_invoice",
          purpose_id: invoice.id,
          user_id: context.user_id,
          amount_cents: invoice.balance_due_cents,
          currency: invoice.currency,
          description: invoice_description(invoice),
          customer: %{
            email: params[:email],
            name: params[:name],
            language: language
          },
          return_url: base <> "/pay/return?payment={payment_id}",
          cancel_url: base <> "/pay/return?payment={payment_id}&cancelled=1",
          save_method: save?,
          consent: %{
            accepted: params[:consent_accepted] == true,
            ip: params[:ip],
            user_agent: params[:user_agent],
            language: language
          },
          consent_terms: consent_terms(context, invoice, language),
          idempotency_key: params[:idempotency_key],
          created_by_id: context.user_id
        },
        now()
      )
    end
  end

  defp invoice_description(invoice) do
    first =
      case invoice[:lines] do
        [%{description: text} | _] when is_binary(text) -> " · " <> text
        _none -> ""
      end

    (invoice.invoice_number || "") <> first
  end

  defp consent_terms(context, invoice, language) do
    %{
      business: business_name(context),
      purpose:
        if(language(language) == "el",
          do: "τις επόμενες χρεώσεις της συνδρομής μου",
          else: "the next charges of my membership"
        ),
      max_amount_cents: invoice.balance_due_cents,
      currency: invoice.currency
    }
  end

  defp business_name(context) do
    case Fiscal.identity_status(context) do
      %{identity: %{trade_name: name}} when is_binary(name) and name != "" -> name
      %{identity: %{legal_name: name}} when is_binary(name) and name != "" -> name
      _none -> "Palee"
    end
  end

  @doc "The member came back from the provider's page: ask the provider now."
  def returned(context, params) do
    intent_id =
      cond do
        is_binary(params[:payment_id]) ->
          params.payment_id

        is_binary(params[:provider_ref]) ->
          case Payments.get_by_ref(context, params.provider_ref) do
            {:ok, payment} -> payment.id
            _none -> nil
          end

        true ->
          nil
      end

    with {:ok, payment} <- my_payment(context, intent_id) do
      Payments.refresh(context, payment.id, params[:transaction_id], now())
    end
  end

  @doc "Dev/test only: completes a sandbox checkout as the provider's page would."
  def sandbox_complete(context, params) do
    with {:ok, payment} <- Payments.get_by_ref(context, params.provider_ref),
         {:ok, _mine} <- my_payment(context, payment.id),
         {:ok, transaction_id} <-
           Payments.sandbox_transaction(
             params.provider_ref,
             params.outcome,
             params[:decline_card]
           ) do
      Payments.refresh(context, payment.id, transaction_id, now())
    end
  end

  def my_payment(_context, nil), do: {:error, :not_found}

  def my_payment(context, id) do
    case Payments.get(context, id) do
      {:ok, %{user_id: user_id} = payment} when user_id == context.user_id -> {:ok, payment}
      _other -> {:error, :not_found}
    end
  end

  def my_methods(context), do: Payments.methods(context, context.user_id)

  def revoke_my_method(context, id),
    do: Payments.revoke_method(context, context.user_id, id, context.user_id, now())

  def set_autopay(context, id, autopay),
    do: Payments.set_autopay(context, context.user_id, id, autopay)

  defp member_invoice(context, invoice_id) do
    case Finance.get_member_profile(context, context.user_id) do
      %{invoices: invoices} ->
        case Enum.find(invoices, &(&1.id == invoice_id)) do
          %{status: status, balance_due_cents: balance} = invoice
          when status in @open_invoice_statuses and balance > 0 ->
            {:ok, invoice}

          %{} ->
            {:error, :invoice_not_payable}

          nil ->
            {:error, :not_found}
        end

      _none ->
        {:error, :not_found}
    end
  end

  defp language(language) when language in ["el", "en"], do: language
  defp language(_language), do: "en"

  # ── Jobs ────────────────────────────────────────────────────────────────

  def process(context, now \\ DateTime.utc_now()), do: Payments.process(context, :due, now)

  @doc """
  Pays due open invoices with the card each member chose for automatic
  payment, within the card's consent. Returns how many charges went
  through or are being retried.
  """
  def autopay(context, now \\ DateTime.utc_now()) do
    if Payments.available?(context) do
      today = Palee.Organizations.local_today(context.organization_id, now)

      context
      |> Payments.autopay_methods()
      |> Enum.flat_map(fn method ->
        member = Map.put(context, :user_id, method.user_id)

        member
        |> due_invoices(today)
        # Money given back on an invoice is a staff decision; never take it again by itself.
        |> Enum.reject(&Payments.refunded?(context, "finance_invoice", &1.id))
        |> Enum.map(fn invoice ->
          Payments.charge_saved(
            member,
            %{
              payment_method_id: method.id,
              purpose_type: "finance_invoice",
              purpose_id: invoice.id,
              amount_cents: invoice.balance_due_cents,
              currency: invoice.currency,
              description: invoice_description(invoice),
              idempotency_key: "autopay:#{invoice.id}:#{invoice.balance_due_cents}"
            },
            now
          )
        end)
      end)
      |> Enum.count(&match?({:ok, %{status: status}} when status != "failed", &1))
    else
      0
    end
  end

  defp due_invoices(context, today) do
    case Finance.get_member_profile(context, context.user_id) do
      %{invoices: invoices} ->
        Enum.filter(invoices, fn invoice ->
          invoice.status in @open_invoice_statuses and invoice.balance_due_cents > 0 and
            (is_nil(invoice.due_date) or Date.compare(invoice.due_date, today) != :gt)
        end)

      _none ->
        []
    end
  end

  defp now, do: DateTime.utc_now()
end
