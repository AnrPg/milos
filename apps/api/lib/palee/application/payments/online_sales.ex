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
  alias Palee.{Finance, Fiscal, Identity, Organizations, Payments, Shop}
  alias Palee.Payments.Domain.{Consent, Withdrawal}

  # ── Packages ────────────────────────────────────────────────────────────

  @doc "The packages a published box sells online, for its public page."
  def public_packages(slug) do
    with {:ok, _box, context} <- PublicBox.resolve(slug) do
      {:ok,
       %{
         packages: context |> sold_online() |> Enum.map(&public_package/1),
         online_payments: Payments.available?(context, "packages"),
         provider: Payments.provider(context),
         withdrawal_days: if(withdrawal_applies?(context), do: Withdrawal.days())
       }}
    end
  end

  defp sold_online(context) do
    context
    |> Finance.list_packages()
    |> Enum.filter(&(&1.active and &1[:sold_online] == true and &1.base_price_cents > 0))
    |> reject_switched_off(context)
  end

  # ADR-260: a purpose the business switched off is not offered online.
  # Without a connected provider the page still lists the packages, with
  # `online_payments: false`.
  defp reject_switched_off(packages, context) do
    if Payments.available?(context),
      do: Enum.filter(packages, &Payments.available?(context, online_purpose(&1))),
      else: packages
  end

  # ADR-260: which «what is paid online» switch covers a package.
  defp online_purpose(%{package_type: "pt_pack"}), do: "personal_training"
  defp online_purpose(%{package_type: type}) when type in ["drop_in", "trial"], do: "drop_in"
  defp online_purpose(_package), do: "packages"

  # ADR-256: the store apps sell only packages with something used in
  # person; `services` carries the contract fields that decide it.
  @service_fields ~w(group_classes.included personal_training.included
                     personal_training.assessments facility.open_gym perks.events)

  defp public_package(package) do
    package
    |> Map.take([
      :id,
      :name,
      :description,
      :package_type,
      :billing_period,
      :base_price_cents,
      :currency
    ])
    |> Map.put(:services, Map.take(package[:fields] || %{}, @service_fields))
  end

  @doc """
  What buying `package_id` costs and the texts the member agrees to.
  `book_slot_id`: the class the purchase books, when it is bought while
  booking (a drop-in or trial for that class has no withdrawal).
  """
  def package_terms(context, package_id, language, book_slot_id \\ nil) do
    with {:ok, package} <- package_for_sale(context, package_id) do
      language = language(language)
      applies = withdrawal_applies?(context) and not dated_visit?(package, book_slot_id)

      {:ok,
       %{
         package: public_package(package),
         available: Payments.available?(context, online_purpose(package)),
         provider: Payments.provider(context),
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
  language, book_slot_id, autopay (with save_card: pay what falls due
  with the saved card).
  """
  def buy_package(context, package_id, params) do
    language = language(params[:language])
    now = DateTime.utc_now()

    with {:ok, package} <- package_for_sale(context, package_id),
         true <-
           Payments.available?(context, online_purpose(package)) ||
             {:error, :online_payments_unavailable},
         {:ok, withdrawal} <-
           Withdrawal.record(
             withdrawal_applies?(context) and not dated_visit?(package, params[:book_slot_id]),
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
            |> put_if("book_slot_id", params[:book_slot_id])
            |> put_if("autopay", autopay(params)),
          idempotency_key: params[:idempotency_key],
          created_by_id: context.user_id
        },
        now
      )
    end
  end

  defp package_for_sale(context, package_id) do
    case Ecto.UUID.cast(package_id) do
      {:ok, id} ->
        case Finance.get_package(context, id) do
          %{active: true, sold_online: true} = package when package.base_price_cents > 0 ->
            {:ok, package}

          %{} ->
            {:error, :package_not_for_sale}

          nil ->
            {:error, :not_found}
        end

      :error ->
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

    with %{} = actor <- Identity.find_by_id(intent.user_id) || {:error, :not_found},
         {:ok, _booking} <- SubmitBooking.call(member, actor, slot_id) do
      :ok
    else
      {:error, reason} ->
        Logger.info("booking after package purchase #{intent.id} refused: #{inspect(reason)}")
    end
  rescue
    # The money and the package are recorded; a booking failure never undoes them.
    error ->
      Logger.error(
        "booking after package purchase #{intent.id} failed: #{Exception.message(error)}"
      )
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

    # The order's Finance payment is recorded by the shop (ADR-190 lineage).
    with {:ok, _order} <-
           Checkout.settle_online(member, intent.purpose_id, %{
             provider: intent.provider,
             reference: intent.provider_transaction_id,
             idempotency_key: "capture:" <> intent.purpose_id
           }) do
      {:ok, %{}}
    end
  end

  # ── helpers ─────────────────────────────────────────────────────────────

  # A single visit or trial bought for one class on a set day and time is a
  # leisure service for a specific date: no right of withdrawal (Directive
  # 2011/83/EU art. 16(l)).
  defp dated_visit?(%{package_type: type}, slot_id)
       when type in ["drop_in", "trial"] and is_binary(slot_id),
       do: true

  defp dated_visit?(_package, _slot_id), do: false

  # Autopay needs the saved card it pays with.
  defp autopay(%{save_card: true, autopay: true}), do: true
  defp autopay(_params), do: nil

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
