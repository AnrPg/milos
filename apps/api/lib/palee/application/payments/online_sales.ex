defmodule Palee.Application.Payments.OnlineSales do
  @moduledoc """
  ADR-248: what members buy online besides invoices.

    * **Packages** the box marks «sold online»: listed on the public box
      page, bought on the provider's page, assigned with their receipt or
      invoice once the provider confirms the money (one Finance
      transaction), optionally followed by booking the class the member
      was trying to book.
    * **Withdrawal** within 14 days where the law gives it (EU, EEA, UK):
      the member asks for the package to start now when buying, and on
      withdrawal gets back the price less the part already used.
    * **Shop orders** placed for online payment, paid on the provider's
      page and settled like a captured order.
  """

  require Logger

  alias Palee.Application.{PublicBox, PublicURL, SubmitBooking}
  alias Palee.Application.Shop.Checkout
  alias Palee.{Finance, Fiscal, Organizations, Payments, Shop}
  alias Palee.Payments.Domain.{Consent, Withdrawal}

  # ── Packages ────────────────────────────────────────────────────────────

  @doc "The packages a published box sells online, for its public page."
  def public_packages(slug) do
    with {:ok, _box, context} <- PublicBox.resolve(slug) do
      {:ok,
       %{
         packages: context |> sold_online() |> Enum.map(&public_package/1),
         online_payments: Payments.available?(context),
         withdrawal_days: if(withdrawal_applies?(context), do: Withdrawal.days())
       }}
    end
  end

  defp sold_online(context) do
    context
    |> Finance.list_packages()
    |> Enum.filter(&(&1.active and &1[:sold_online] == true and &1.base_price_cents > 0))
  end

  defp public_package(package) do
    Map.take(package, [
      :id,
      :name,
      :description,
      :package_type,
      :billing_period,
      :base_price_cents,
      :currency
    ])
  end

  @doc "What buying `package_id` costs and the texts the member agrees to."
  def package_terms(context, package_id, language) do
    with {:ok, package} <- package_for_sale(context, package_id) do
      language = language(language)
      applies = withdrawal_applies?(context)

      {:ok,
       %{
         package: public_package(package),
         available: Payments.available?(context),
         withdrawal_days: if(applies, do: Withdrawal.days()),
         start_now_text: if(applies, do: Withdrawal.text(language)),
         consent_text: Consent.text(language, card_terms(context, package, language)),
         consent_version: Consent.version()
       }}
    end
  end

  @doc """
  Opens a checkout for a package (and, with `book_slot_id`, the class to
  book once it is paid). `params`: idempotency_key, save_card,
  consent_accepted, start_now (required where withdrawal applies),
  language, book_slot_id.
  """
  def buy_package(context, package_id, params) do
    language = language(params[:language])
    now = DateTime.utc_now()

    with {:ok, package} <- package_for_sale(context, package_id),
         {:ok, withdrawal} <-
           Withdrawal.record(
             withdrawal_applies?(context),
             %{start_now: params[:start_now], language: language},
             now
           ) do
      base = PublicURL.base_url() |> String.trim_trailing("/")

      Payments.start_checkout(
        context,
        %{
          purpose_type: "membership_package",
          purpose_id: package.id,
          user_id: context.user_id,
          amount_cents: package.base_price_cents,
          currency: package.currency,
          description: package.name,
          customer: %{language: language},
          return_url: base <> "/pay/return?payment={payment_id}",
          cancel_url: base <> "/pay/return?payment={payment_id}&cancelled=1",
          save_method: params[:save_card] == true,
          consent: %{
            accepted: params[:consent_accepted] == true,
            ip: params[:ip],
            user_agent: params[:user_agent],
            language: language
          },
          consent_terms: card_terms(context, package, language),
          metadata:
            %{"withdrawal" => withdrawal, "package_name" => package.name}
            |> put_if("book_slot_id", params[:book_slot_id]),
          idempotency_key: params[:idempotency_key],
          created_by_id: context.user_id
        },
        now
      )
    end
  end

  defp package_for_sale(context, package_id) do
    case Finance.get_package(context, package_id) do
      {:ok, %{active: true, sold_online: true} = package} when package.base_price_cents > 0 ->
        {:ok, package}

      {:ok, _package} ->
        {:error, :package_not_for_sale}

      _missing ->
        {:error, :not_found}
    end
  end

  defp card_terms(context, package, language) do
    %{
      business: business_name(context),
      purpose:
        if(language == "el",
          do: "τις επόμενες χρεώσεις του πακέτου «#{package.name}»",
          else: "the next charges of the package “#{package.name}”"
        ),
      max_amount_cents: package.base_price_cents,
      currency: package.currency
    }
  end

  @doc """
  Fulfils a package purchase: the member's membership (created on a first
  purchase), the package and its document in one Finance transaction,
  then the class booking asked for. Idempotent per payment.
  """
  def fulfil_package(context, intent, record_online) do
    user_id = intent.user_id

    with {:ok, _membership} <- ensure_membership(context, user_id),
         {:ok, received} <-
           record_online.(context, user_id, %{
             "purchase_package_id" => intent.purpose_id,
             "amount_cents" => intent.amount_cents,
             "currency" => intent.currency,
             "paid_on" =>
               context.organization_id
               |> Organizations.local_today(intent.succeeded_at || DateTime.utc_now())
               |> Date.to_iso8601(),
             "idempotency_key" => "payment-intent:" <> intent.id,
             "payment_intent_id" => intent.id,
             "provider" => intent.provider,
             "provider_transaction_id" => intent.provider_transaction_id
           }) do
      unless received.replayed, do: book_after_purchase(context, intent)
      {:ok, %{finance_payment_id: received.payment.id}}
    end
  end

  defp ensure_membership(context, user_id) do
    case Finance.get_member_profile(context, user_id) do
      %{membership: %{} = membership} ->
        {:ok, membership}

      _none ->
        Finance.upsert_membership(context, user_id, %{
          user_type_snapshot: "member",
          status: "active",
          signup_source: "direct"
        })
    end
  end

  # A full class does not undo the purchase: the package stays theirs.
  defp book_after_purchase(context, %{metadata: %{"book_slot_id" => slot_id}} = intent)
       when is_binary(slot_id) do
    member = context |> Map.put(:user_id, intent.user_id)

    case SubmitBooking.call(member, %{id: intent.user_id}, slot_id) do
      {:ok, _booking} ->
        :ok

      {:error, reason} ->
        Logger.info("booking after package purchase #{intent.id} refused: #{inspect(reason)}")
    end
  end

  defp book_after_purchase(_context, _intent), do: :ok

  @doc "The member withdraws from a package bought online within 14 days."
  def withdraw(context, payment_id) do
    now = DateTime.utc_now()
    today = Organizations.local_today(context.organization_id, now)

    with {:ok, payment} <- Payments.get(context, payment_id),
         true <- payment.user_id == context.user_id || {:error, :not_found},
         true <-
           payment.purpose_type == "membership_package" || {:error, :withdrawal_not_available},
         true <-
           (payment.status == "succeeded" and payment.fulfilment_status == "done") ||
             {:error, :withdrawal_not_available},
         :ok <- Withdrawal.open?(payment.metadata["withdrawal"], now),
         {:ok, facts} <- Finance.withdrawal_facts(context, payment.finance_payment_id),
         true <- facts.status != "cancelled" || {:error, :already_withdrawn} do
      left = payment.amount_cents - payment.refunded_cents
      refund = min(Withdrawal.refund_cents(payment.amount_cents, facts, today), left)

      with {:ok, refund} <- refund_withdrawal(context, payment, refund),
           {:ok, _subscription} <-
             Finance.withdraw_subscription(context, facts.subscription_id, today) do
        {:ok, %{refund: refund, refunded_cents: refund[:amount_cents] || 0}}
      end
    end
  end

  defp refund_withdrawal(_context, _payment, 0), do: {:ok, %{amount_cents: 0}}

  defp refund_withdrawal(context, payment, cents) do
    Payments.refund(
      context,
      payment.id,
      %{
        amount_cents: cents,
        reason: "Υπαναχώρηση / withdrawal",
        idempotency_key: "withdrawal:" <> payment.id
      },
      context.user_id,
      DateTime.utc_now()
    )
  end

  # ── Shop ────────────────────────────────────────────────────────────────

  @doc "Opens a checkout for the member's unpaid online shop order."
  def pay_shop_order(context, order_id, params) do
    with %{} = order <- Shop.get_order(context, order_id) || {:error, :not_found},
         true <- order.user_id == context.user_id || {:error, :not_found},
         true <- order.payment_status == :pending_payment || {:error, :order_not_payable} do
      base = PublicURL.base_url() |> String.trim_trailing("/")
      language = language(params[:language])

      Payments.start_checkout(
        context,
        %{
          purpose_type: "shop_order",
          purpose_id: order.id,
          user_id: context.user_id,
          amount_cents: order.total_cents,
          currency: order.currency,
          description: "#{order.number}",
          customer: %{language: language},
          return_url: base <> "/pay/return?payment={payment_id}",
          cancel_url: base <> "/pay/return?payment={payment_id}&cancelled=1",
          save_method: false,
          idempotency_key: params[:idempotency_key],
          created_by_id: context.user_id
        },
        DateTime.utc_now()
      )
    end
  end

  @doc "Fulfils a paid shop order (idempotent: a paid order stays paid)."
  def fulfil_shop_order(context, intent) do
    member = Map.put(context, :user_id, intent.user_id)

    with {:ok, order} <-
           Checkout.settle_online(member, intent.purpose_id, %{
             provider: intent.provider,
             reference: intent.provider_transaction_id,
             idempotency_key: "capture:" <> intent.purpose_id
           }) do
      {:ok, %{finance_payment_id: order[:finance_payment_id]}}
    end
  end

  # ── helpers ─────────────────────────────────────────────────────────────

  defp withdrawal_applies?(context) do
    case Fiscal.identity_status(context) do
      %{identity: %{country_code: country}} when is_binary(country) ->
        Withdrawal.applies?(country)

      # Unknown country: offer the consumer the stronger right.
      _none ->
        true
    end
  end

  defp business_name(context) do
    case Fiscal.identity_status(context) do
      %{identity: %{trade_name: name}} when is_binary(name) and name != "" -> name
      %{identity: %{legal_name: name}} when is_binary(name) and name != "" -> name
      _none -> "Palee"
    end
  end

  defp language(language) when language in ["el", "en"], do: language
  defp language(_language), do: "en"

  defp put_if(map, _key, nil), do: map
  defp put_if(map, key, value), do: Map.put(map, key, value)
end
