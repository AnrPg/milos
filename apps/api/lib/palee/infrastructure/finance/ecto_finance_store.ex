defmodule Palee.Infrastructure.Finance.EctoFinanceStore do
  @behaviour Palee.Finance.Ports.FinanceStore

  import Ecto.Query

  alias Palee.Finance.FinanceAccountingStore
  alias Palee.Finance.FinanceSubscriptionFreeze

  alias Palee.Finance.{
    FinanceCorporateClient,
    FinanceCorporateInvoice,
    FinanceCorporatePayment,
    FinanceSubscriptionBeneficiary
  }

  alias Palee.Finance.{
    FinanceCreditLedgerEntry,
    FinanceEntitlementUsageEntry,
    FinanceInvoice,
    FinanceInvoiceLine,
    FinanceSetting,
    Membership,
    MembershipPackage,
    MembershipPackageSubscription,
    MembershipPayment,
    FinancePaymentReversal,
    PromotionCampaign,
    PromotionCode,
    PromotionRedemption,
    ReferralEvent,
    ReferralProgram,
    ReferralReward
  }

  alias Palee.Finance.Domain.{
    AllowancePeriod,
    CorporateInvoicePolicy,
    CreditLedger,
    EntitlementPlan,
    EntitlementPolicy,
    InvoiceLifecycle,
    InvoiceNumber,
    MembershipLifecycle,
    MembershipLinks,
    MemberRenewal,
    PackageCode,
    PackageContract,
    PaymentModelPolicy,
    PromotionRedemptionPolicy,
    ReceivedPayment,
    ReferralLifecycle,
    RevenueBreakdown,
    ReferralPolicy,
    ReferralRewardFulfillment,
    SubscriptionSelection,
    SubscriptionTerms
  }

  alias Palee.Repo
  alias Palee.Infrastructure.Tenancy.{GymClock, RepoContext}

  @impl true
  def create_package(params) do
    params = string_key_map(params)

    with {:ok, attrs} <- package_contract_attrs(params, nil) do
      Repo.transaction(fn ->
        attrs = Map.put(attrs, "code", available_package_code(params["code"] || params["name"]))

        %MembershipPackage{}
        |> MembershipPackage.changeset(attrs)
        |> Repo.insert()
        |> case do
          {:ok, package} -> normalize_package(package)
          {:error, reason} -> Repo.rollback(reason)
        end
      end)
    end
  end

  @impl true
  def update_package(id, params) do
    Repo.transaction(fn ->
      package =
        MembershipPackage
        |> tenant_scope()
        |> where([candidate], candidate.id == ^id)
        |> lock("FOR UPDATE")
        |> Repo.one()

      if is_nil(package), do: Repo.rollback(:not_found)

      retiring? = package.active && requested_inactive?(params)

      if retiring? && effective_subscriptions_for_package(package.id) != [],
        do: Repo.rollback(:package_retirement_reconciliation_required)

      params = string_key_map(params)

      attrs =
        case package_contract_attrs(params, package) do
          {:ok, attrs} -> attrs
          {:error, reason} -> Repo.rollback(reason)
        end

      if Map.has_key?(attrs, "package_type") && package.package_type != attrs["package_type"] &&
           effective_subscriptions_for_package(package.id) != [],
         do: Repo.rollback(:package_type_change_requires_copy)

      # ADR-096: codes are immutable once assigned; legacy packages without a
      # code receive one derived from their name on the next save.
      attrs =
        if is_nil(package.code),
          do: Map.put(attrs, "code", available_package_code(params["name"] || package.name)),
          else: Map.delete(attrs, "code")

      package
      |> MembershipPackage.changeset(attrs)
      |> Repo.update()
      |> case do
        {:ok, updated} -> normalize_package(updated)
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  @impl true
  def retire_package(id, replacement_package_by_role) do
    replacements = string_key_map(replacement_package_by_role || %{})

    Repo.transaction(fn ->
      source =
        MembershipPackage
        |> tenant_scope()
        |> where([package], package.id == ^id)
        |> lock("FOR UPDATE")
        |> Repo.one()

      if is_nil(source), do: Repo.rollback(:not_found)

      subscriptions = effective_subscriptions_for_package(source.id)

      memberships =
        Map.new(subscriptions, &{&1.membership_id, locked_membership(&1.membership_id)})

      affected_roles =
        memberships
        |> Map.values()
        |> Enum.map(& &1.user_type_snapshot)
        |> Enum.uniq()

      replacement_packages =
        Map.new(affected_roles, fn role ->
          replacement_id = replacements[role]

          replacement =
            replacement_id &&
              MembershipPackage
              |> tenant_scope()
              |> where([package], package.id == ^replacement_id)
              |> Repo.one()

          if is_nil(replacement_id), do: Repo.rollback({:package_replacement_required, role})

          if is_nil(replacement) or replacement.active == false or replacement.id == source.id,
            do: Repo.rollback(:invalid_package_replacement)

          {role, replacement}
        end)

      Enum.each(subscriptions, fn subscription ->
        membership = Map.fetch!(memberships, subscription.membership_id)
        replacement = Map.fetch!(replacement_packages, membership.user_type_snapshot)

        subscription
        |> MembershipPackageSubscription.changeset(%{"status" => "cancelled"})
        |> Repo.update!()

        %MembershipPackageSubscription{}
        |> MembershipPackageSubscription.changeset(%{
          "membership_id" => membership.id,
          "membership_package_id" => replacement.id,
          "status" => "active",
          "starts_on" => GymClock.today(),
          "ends_on" => subscription.ends_on,
          "package_code_snapshot" => package_identity_snapshot(replacement),
          "package_family_snapshot" => replacement.family,
          "billing_period_snapshot" => replacement.billing_period,
          "price_cents_snapshot" => replacement.base_price_cents,
          "params_snapshot" => replacement.params || %{}
        })
        |> Repo.insert!()

        refresh_entitlement_snapshot(membership.id)
      end)

      retired =
        source
        |> MembershipPackage.changeset(%{"active" => false})
        |> Repo.update!()

      %{
        package: normalize_package(retired),
        reassigned_count: length(subscriptions),
        affected_by_role:
          Enum.frequencies(Enum.map(Map.values(memberships), & &1.user_type_snapshot))
      }
    end)
  end

  @impl true
  def list_packages do
    MembershipPackage
    |> tenant_scope()
    |> order_by([package], asc: package.code)
    |> Repo.all()
    |> Enum.map(&normalize_package/1)
  end

  @impl true
  def get_package(id) do
    case tenant_scope(MembershipPackage) |> where([package], package.id == ^id) |> Repo.one() do
      nil -> nil
      %MembershipPackage{} = package -> normalize_package(package)
    end
  end

  @impl true
  def upsert_membership(user_id, params) do
    params =
      params
      |> string_key_map()
      |> Map.put("user_id", user_id)
      |> derive_membership_status()

    Repo.transaction(fn ->
      existing =
        tenant_scope(Membership)
        |> where([membership], membership.user_id == ^user_id)
        |> Repo.one()

      guard_commitment!(existing, params)

      membership =
        case existing do
          nil ->
            %Membership{}
            |> Membership.changeset(params)
            |> Repo.insert()

          %Membership{} = membership ->
            membership
            |> Membership.changeset(params)
            |> Repo.update()
        end
        |> case do
          {:ok, membership} -> membership
          {:error, reason} -> Repo.rollback(reason)
        end

      refresh_entitlement_snapshot(membership.id)

      Membership
      |> tenant_scope()
      |> where([m], m.id == ^membership.id)
      |> Repo.one!()
      |> normalize_membership()
    end)
  end

  @impl true
  def get_member_profile(user_id) do
    case tenant_scope(Membership)
         |> where([membership], membership.user_id == ^user_id)
         |> Repo.one() do
      nil ->
        nil

      %Membership{} = membership ->
        %{
          membership: normalize_membership(membership),
          package_subscriptions: list_subscriptions(membership.id),
          active_package_subscription: active_subscription_for_membership(membership.id),
          invoices: list_invoices(membership.id),
          payments: list_payments(membership.id),
          payment_reversals: list_payment_reversals(membership.id),
          promotion_redemptions: list_redemptions(membership.id),
          credit_ledger_entries: list_credit_ledger_entries(membership.id),
          credit_balance: credit_balance(membership.id),
          entitlement: entitlement_for_membership(membership)
        }
    end
  end

  # ADR-190: what a shop sale needs to know about the buyer's membership:
  # its id (the invoice's owner) and the package member discount when its
  # scope covers products (ADR-097).
  @impl true
  def member_shop_terms(user_id) do
    case tenant_scope(Membership)
         |> where([membership], membership.user_id == ^user_id)
         |> Repo.one() do
      nil ->
        nil

      %Membership{} = membership ->
        terms =
          case effective_subscription(membership.id, GymClock.today()) do
            nil -> %{}
            subscription -> package_terms(subscription.params_snapshot)
          end

        scope = terms[:member_discount_scope] || []

        %{
          membership_id: membership.id,
          member_discount_percent:
            if("products" in scope, do: terms[:member_discount_percent], else: nil)
        }
    end
  end

  @impl true
  def search_member_summaries(params) do
    params = string_key_map(params || %{})
    user_ids = normalize_uuid_list(params["user_ids"])
    limit = parse_integer(params["limit"], 50) |> min(100_000) |> max(1)

    from(membership in tenant_scope(Membership), as: :membership)
    |> maybe_filter_user_ids(user_ids)
    |> maybe_filter_membership_status(params["membership_status"])
    |> maybe_filter_user_type(params["user_type"])
    |> maybe_filter_package_code(params["package_code"])
    |> maybe_filter_package_family(params["package_family"])
    |> order_by([membership], desc: membership.updated_at)
    |> limit(^limit)
    |> Repo.all()
    |> member_search_summaries()
  end

  @impl true
  def assign_package(membership_id, package_id, params) do
    Repo.transaction(fn ->
      with %Membership{} = membership <- locked_membership(membership_id),
           %MembershipPackage{} = package <-
             tenant_scope(MembershipPackage)
             |> where([package], package.id == ^package_id)
             |> Repo.one(),
           :ok <- validate_package_active(package),
           :ok <-
             SubscriptionSelection.eligible?(
               package.id,
               package.params || %{},
               list_subscriptions(membership.id)
             ),
           {:ok, params} <- payment_model_params(membership, package, string_key_map(params)) do
        subscription = insert_subscription!(membership, package, params)
        rejoin!(membership)
        refresh_entitlement_snapshot(membership.id)
        normalize_subscription(subscription)
      else
        nil -> Repo.rollback(:not_found)
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp insert_subscription!(membership, package, params) do
    params =
      params
      |> put_subscription_window(package)
      |> Map.merge(%{
        "membership_id" => membership.id,
        "membership_package_id" => package.id,
        "package_code_snapshot" => package_identity_snapshot(package),
        "package_family_snapshot" => package.family,
        "billing_period_snapshot" => package.billing_period,
        "price_cents_snapshot" => price_snapshot(params, package),
        "params_snapshot" => package.params || %{}
      })

    %MembershipPackageSubscription{}
    |> MembershipPackageSubscription.changeset(params)
    |> Repo.insert()
    |> case do
      {:ok, subscription} -> subscription
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  # ADR-167: a season sells its package at the season's price; every other
  # assignment takes the package's own price.
  defp price_snapshot(%{"price_cents_snapshot" => price}, _package)
       when is_integer(price) and price >= 0,
       do: price

  defp price_snapshot(_params, package), do: package.base_price_cents

  # ADR-098: add-ons attach to a compatible base and follow it; corporate
  # seats are created only by enrollment, never assigned directly.
  defp payment_model_params(membership, package, params) do
    case PackageContract.type_from_params(package.params) do
      "add_on" ->
        compatible = package_terms(package.params)[:compatible_package_ids] || "all"

        with {:ok, base} <-
               membership.id
               |> effective_subscriptions(GymClock.today())
               |> PaymentModelPolicy.add_on_base(compatible, params["base_subscription_id"]) do
          {:ok,
           params
           |> Map.put("base_subscription_id", base.id)
           |> Map.put("starts_on", params["starts_on"] || GymClock.today())}
        end

      "corporate" ->
        if params["corporate_client_id"],
          do: {:ok, params},
          else: {:error, :corporate_package_requires_enrollment}

      _other ->
        {:ok, Map.drop(params, ["base_subscription_id", "corporate_client_id"])}
    end
  end

  @impl true
  def record_payment(membership_id, params) do
    params =
      params
      |> string_key_map()
      |> Map.put("membership_id", membership_id)
      |> Map.put_new("paid_on", GymClock.today())

    Repo.transaction(fn ->
      with %Membership{} = membership <- locked_membership(membership_id),
           :ok <- validate_payment_links(membership.id, params),
           :ok <- validate_invoice_payment_application(params) do
        payment =
          %MembershipPayment{}
          |> MembershipPayment.changeset(params)
          |> Repo.insert()
          |> case do
            {:ok, payment} -> payment
            {:error, reason} -> Repo.rollback(reason)
          end

        refresh_invoice_and_entitlement(payment.finance_invoice_id, membership.id)
        normalize_payment(payment)
      else
        nil -> Repo.rollback(:not_found)
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  @impl true
  def create_receipt(membership_id, params),
    do: create_paid_document(membership_id, :receipt, params)

  # ADR-222: money received at the desk. The box's billing setup picks the
  # document; one idempotency key records the money once, however often the
  # request is retried (the membership row lock serialises retries).
  @impl true
  def receive_payment(membership_id, params) do
    params = string_key_map(params)

    with :ok <- ReceivedPayment.validate(params) do
      document =
        ReceivedPayment.document(
          get_finance_settings().document_mode,
          params["finance_invoice_id"]
        )

      Repo.transaction(fn ->
        with %Membership{} = membership <- locked_membership(membership_id),
             nil <- payment_by_idempotency_key(membership.id, params["idempotency_key"]),
             :ok <- ReceivedPayment.validate_purpose(document, params),
             {:ok, result} <- receive_into(document, membership.id, params) do
          Map.put(result, :replayed, false)
        else
          %MembershipPayment{} = payment ->
            payment |> received_payment_result() |> Map.put(:replayed, true)

          nil ->
            Repo.rollback(:not_found)

          {:error, reason} ->
            Repo.rollback(reason)
        end
      end)
    end
  end

  defp receive_into(:settle_invoice, membership_id, params) do
    with {:ok, payment} <-
           record_payment(membership_id, %{
             "finance_invoice_id" => params["finance_invoice_id"],
             "amount_cents" => params["amount_cents"],
             "currency" => params["currency"] || "EUR",
             "paid_on" => params["paid_on"],
             "payment_method" => params["payment_method"],
             "payment_status" => "paid",
             "notes" => params["notes"],
             "params" => %{
               "idempotency_key" => params["idempotency_key"],
               "created_by_id" => params["created_by_id"]
             }
           }) do
      {:ok, received_payment_result(Repo.get!(MembershipPayment, payment.id))}
    end
  end

  defp receive_into(document, membership_id, params) do
    create_paid_document(membership_id, document, params)
  end

  defp payment_by_idempotency_key(membership_id, key) do
    MembershipPayment
    |> tenant_scope()
    |> where([payment], payment.membership_id == ^membership_id and is_nil(payment.deleted_at))
    |> where([payment], fragment("?->>'idempotency_key' = ?", payment.params, ^key))
    |> limit(1)
    |> Repo.one()
  end

  defp received_payment_result(%MembershipPayment{finance_invoice_id: invoice_id} = payment) do
    invoice = FinanceInvoice |> Repo.get!(invoice_id) |> normalize_invoice_with_balance()
    subscription = invoice_subscription(invoice.membership_package_subscription_id)

    %{
      document_type: (invoice.params || %{})["document_kind"] || "invoice",
      reference: invoice.invoice_number,
      issued_on: payment.paid_on,
      amount_cents: payment.amount_cents,
      currency: payment.currency,
      description: invoice_description(invoice),
      membership_package_subscription_id: invoice.membership_package_subscription_id,
      package_name: subscription && subscription.package_name,
      package_code_snapshot: subscription && subscription.package_code_snapshot,
      package_family_snapshot: subscription && subscription.package_family_snapshot,
      invoice: invoice,
      payment: normalize_payment(payment)
    }
  end

  # What the money was for: the invoice's first line, else its notes.
  defp invoice_description(invoice) do
    FinanceInvoiceLine
    |> where([line], line.finance_invoice_id == ^invoice.id)
    |> order_by([line], asc: line.inserted_at, asc: line.id)
    |> select([line], line.description)
    |> limit(1)
    |> Repo.one()
    |> Kernel.||(invoice.notes)
  end

  defp invoice_subscription(nil), do: nil

  defp invoice_subscription(subscription_id) do
    case Repo.get(MembershipPackageSubscription, subscription_id) do
      nil -> nil
      subscription -> normalize_subscription(subscription)
    end
  end

  # A document issued already paid: a receipt (ADR-189 receipt mode) or, in
  # invoice mode, a paid invoice (ADR-222).
  defp create_paid_document(membership_id, document, params) do
    params = string_key_map(params)
    amount_cents = parse_integer(params["amount_cents"], 0)
    paid_on = parse_date(params["paid_on"], GymClock.today())
    description = params["description"] || params["notes"] || "Payment received"
    currency = params["currency"] || "EUR"
    kind = ReceivedPayment.document_kind(document)

    Repo.transaction(fn ->
      invoice_params =
        %{
          "invoice_type" => "manual",
          "issue_date" => paid_on,
          "due_date" => if(document == :invoice, do: paid_on),
          "currency" => currency,
          "amount_cents" => amount_cents,
          "description" => description,
          "membership_package_subscription_id" => params["membership_package_subscription_id"],
          "notes" => params["notes"],
          "params" => %{
            "document_kind" => kind,
            "idempotency_key" => params["idempotency_key"]
          }
        }
        |> maybe_put_charge_line(params["charge_category"])

      with true <- amount_cents > 0 || {:error, :invalid_receipt_amount},
           {:ok, invoice} <- create_invoice(membership_id, invoice_params),
           {:ok, _issued_invoice} <-
             issue_invoice(invoice.id, %{"issue_date" => paid_on, "due_date" => paid_on}),
           {:ok, payment} <-
             record_payment(membership_id, %{
               "finance_invoice_id" => invoice.id,
               "membership_package_subscription_id" =>
                 params["membership_package_subscription_id"],
               "amount_cents" => amount_cents,
               "currency" => currency,
               "paid_on" => paid_on,
               "payment_method" => params["payment_method"] || "cash",
               "payment_status" => "paid",
               "notes" => params["notes"],
               "params" => %{
                 "document_kind" => kind,
                 "idempotency_key" => params["idempotency_key"],
                 "created_by_id" => params["created_by_id"]
               }
             }) do
        received_payment_result(Repo.get!(MembershipPayment, payment.id))
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  # A payment for something other than a πακέτο συνδρομής keeps its charge
  # category (product, personal training, event, other) on its line.
  defp maybe_put_charge_line(%{"membership_package_subscription_id" => id} = params, _category)
       when is_binary(id) and id != "",
       do: params

  defp maybe_put_charge_line(params, category) when is_binary(category) and category != "" do
    Map.put(params, "lines", [
      %{
        "line_type" => "manual_charge",
        "charge_category" => category,
        "description" => params["description"],
        "quantity" => 1,
        "unit_amount_cents" => params["amount_cents"]
      }
    ])
  end

  defp maybe_put_charge_line(params, _category), do: params

  @impl true
  def create_manual_credit(membership_id, params) do
    params = string_key_map(params)

    Repo.transaction(fn ->
      with %Membership{} = membership <- locked_membership(membership_id),
           :ok <- require_request_id(params),
           amount_cents <- parse_integer(params["amount_cents"], 0),
           :ok <- CreditLedger.validate_manual_grant(amount_cents),
           {:ok, entry} <-
             create_credit_entry(%{
               "membership_id" => membership.id,
               "user_id" => membership.user_id,
               "source_type" => "manual_credit",
               "entry_type" => "grant",
               "amount_cents" => amount_cents,
               "currency" => "EUR",
               "occurred_on" => GymClock.today(),
               "occurred_at" => utc_now(),
               "description" => params["description"] || params["notes"],
               "created_by_id" => params["created_by_id"],
               "idempotency_key" =>
                 scoped_idempotency_key("manual_credit", membership.id, params),
               "params" => manual_credit_params(params)
             }) do
        entry
      else
        nil -> Repo.rollback(:not_found)
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  @impl true
  def apply_credit_to_payment(membership_id, payment_id, params) do
    params = string_key_map(params)

    Repo.transaction(fn ->
      with %Membership{} = membership <- locked_membership(membership_id),
           %MembershipPayment{} = payment <- locked_payment(payment_id),
           :ok <- require_request_id(params),
           :ok <-
             MembershipLinks.validate_optional_link(
               :membership_payment_id,
               membership.id,
               payment.membership_id
             ),
           :ok <- CreditLedger.validate_payment_status(payment.payment_status),
           amount_cents <- parse_integer(params["amount_cents"], 0),
           available_cents <- credit_balance(membership.id),
           remaining_payment_cents <- remaining_payment_credit_capacity(payment),
           :ok <-
             CreditLedger.validate_application(
               available_cents,
               amount_cents,
               remaining_payment_cents
             ),
           {:ok, entry} <-
             create_credit_entry(%{
               "membership_id" => membership.id,
               "user_id" => membership.user_id,
               "membership_payment_id" => payment.id,
               "source_type" => "payment_application",
               "entry_type" => "application",
               "amount_cents" => -amount_cents,
               "currency" => payment.currency || "EUR",
               "occurred_on" => GymClock.today(),
               "occurred_at" => utc_now(),
               "description" => params["description"] || params["notes"],
               "created_by_id" => params["created_by_id"],
               "idempotency_key" =>
                 scoped_idempotency_key(
                   "payment_application:#{payment.id}",
                   membership.id,
                   params
                 ),
               "params" => credit_application_params(params)
             }) do
        entry
      else
        nil -> Repo.rollback(:not_found)
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  @impl true
  def reverse_payment(membership_id, payment_id, params) do
    params = string_key_map(params)

    Repo.transaction(fn ->
      with %Membership{} = membership <- locked_membership(membership_id),
           %MembershipPayment{} = payment <- locked_payment(payment_id),
           :ok <- require_request_id(params),
           :ok <-
             MembershipLinks.validate_optional_link(
               :membership_payment_id,
               membership.id,
               payment.membership_id
             ),
           :ok <- validate_payment_credit_reversals(payment.id),
           amount_cents <- parse_integer(params["amount_cents"], 0),
           already_reversed_cents <- payment_reversed_cents(payment.id),
           :ok <-
             InvoiceLifecycle.validate_payment_reversal(
               payment.payment_status,
               payment.amount_cents,
               already_reversed_cents,
               amount_cents
             ),
           {:ok, reversal} <-
             create_payment_reversal(%{
               "membership_id" => membership.id,
               "user_id" => membership.user_id,
               "membership_payment_id" => payment.id,
               "finance_invoice_id" => payment.finance_invoice_id,
               "reversal_type" => params["reversal_type"] || payment_reversal_type(payment),
               "amount_cents" => amount_cents,
               "currency" => payment.currency || "EUR",
               "occurred_on" => GymClock.today(),
               "occurred_at" => utc_now(),
               "reason" => params["reason"] || params["description"] || params["notes"],
               "created_by_id" => params["created_by_id"],
               "idempotency_key" =>
                 scoped_finance_key("payment_reversal:#{payment.id}", membership.id, params),
               "params" => reversal_params(params, payment.id)
             }),
           # ADR-126: the refund receipt is issued in the same transaction as
           # the reversal fact, so a receipt number is never consumed for a
           # reversal that rolled back (and replays return the same receipt).
           {:ok, _receipt} <-
             FinanceAccountingStore.issue_refund_receipt(reversal.id, params["receipt_party"]) do
        refresh_invoice_and_entitlement(payment.finance_invoice_id, membership.id)
        reversal
      else
        nil -> Repo.rollback(:not_found)
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  @impl true
  def reverse_credit_ledger_entry(membership_id, entry_id, params) do
    params = string_key_map(params)

    Repo.transaction(fn ->
      with %Membership{} = membership <- locked_membership(membership_id),
           %FinanceCreditLedgerEntry{} = original_entry <- locked_credit_ledger_entry(entry_id),
           :ok <- require_request_id(params),
           :ok <-
             MembershipLinks.validate_optional_link(
               :credit_ledger_entry_id,
               membership.id,
               original_entry.membership_id
             ),
           amount_cents <- parse_integer(params["amount_cents"], 0),
           already_reversed_cents <- credit_entry_reversed_cents(original_entry.id),
           :ok <-
             CreditLedger.validate_reversal(original_entry, already_reversed_cents, amount_cents),
           {:ok, reversal} <-
             create_credit_entry(%{
               "membership_id" => membership.id,
               "user_id" => membership.user_id,
               "membership_payment_id" => original_entry.membership_payment_id,
               "finance_invoice_id" => original_entry.finance_invoice_id,
               "finance_invoice_line_id" => original_entry.finance_invoice_line_id,
               "source_type" => "reversal",
               "entry_type" => "reversal",
               "amount_cents" => amount_cents,
               "currency" => original_entry.currency || "EUR",
               "occurred_on" => GymClock.today(),
               "occurred_at" => utc_now(),
               "description" => params["reason"] || params["description"] || params["notes"],
               "created_by_id" => params["created_by_id"],
               "reversed_credit_ledger_entry_id" => original_entry.id,
               "idempotency_key" =>
                 scoped_finance_key("credit_reversal:#{original_entry.id}", membership.id, params),
               "params" => reversal_params(params, original_entry.id)
             }) do
        refresh_invoice_and_entitlement(original_entry.finance_invoice_id, membership.id)
        reversal
      else
        nil -> Repo.rollback(:not_found)
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  @impl true
  def reverse_credit_grant(membership_id, entry_id, params) do
    params = string_key_map(params)

    Repo.transaction(fn ->
      with %Membership{} = membership <- locked_membership(membership_id),
           %FinanceCreditLedgerEntry{} = original_entry <- locked_credit_ledger_entry(entry_id),
           :ok <- require_request_id(params),
           :ok <-
             MembershipLinks.validate_optional_link(
               :credit_ledger_entry_id,
               membership.id,
               original_entry.membership_id
             ),
           amount_cents <- parse_integer(params["amount_cents"], 0),
           :ok <-
             CreditLedger.validate_grant_reversal(
               original_entry,
               credit_grant_reversed_cents(original_entry.id),
               amount_cents,
               credit_balance(membership.id)
             ),
           {:ok, reversal} <-
             create_credit_entry(%{
               "membership_id" => membership.id,
               "user_id" => membership.user_id,
               "source_type" => "reversal",
               "entry_type" => "reversal",
               "amount_cents" => -amount_cents,
               "currency" => original_entry.currency || "EUR",
               "occurred_on" => GymClock.today(),
               "occurred_at" => utc_now(),
               "description" => params["reason"],
               "created_by_id" => params["created_by_id"],
               "reversed_credit_ledger_entry_id" => original_entry.id,
               "idempotency_key" =>
                 scoped_finance_key("credit_grant_reversal:#{original_entry.id}", membership.id, params),
               "params" => reversal_params(params, original_entry.id)
             }) do
        refresh_invoice_and_entitlement(nil, membership.id)
        reversal
      else
        nil -> Repo.rollback(:not_found)
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp credit_grant_reversed_cents(entry_id) do
    FinanceCreditLedgerEntry
    |> where([entry], entry.reversed_credit_ledger_entry_id == ^entry_id)
    |> where([entry], entry.amount_cents < 0)
    |> where([entry], is_nil(entry.deleted_at))
    |> Repo.aggregate(:sum, :amount_cents)
    |> case do
      nil -> 0
      value -> -value
    end
  end

  @impl true
  def get_invoice(invoice_id) do
    case FinanceInvoice |> tenant_scope() |> Repo.get(invoice_id) do
      nil -> {:error, :not_found}
      %FinanceInvoice{deleted_at: deleted_at} when not is_nil(deleted_at) -> {:error, :not_found}
      invoice -> {:ok, invoice}
    end
  end

  @impl true
  def update_invoice_params(invoice_id, params) do
    case FinanceInvoice |> tenant_scope() |> Repo.get(invoice_id) do
      nil ->
        {:error, :not_found}

      %FinanceInvoice{deleted_at: deleted_at} when not is_nil(deleted_at) ->
        {:error, :not_found}

      invoice ->
        invoice
        |> FinanceInvoice.changeset(%{params: params})
        |> Repo.update()
        |> normalize_result(&normalize_invoice/1)
    end
  end

  @impl true
  def update_invoice(invoice_id, params) do
    params = string_key_map(params)

    case FinanceInvoice |> tenant_scope() |> Repo.get(invoice_id) do
      nil ->
        {:error, :not_found}

      %FinanceInvoice{deleted_at: deleted_at} when not is_nil(deleted_at) ->
        {:error, :not_found}

      %FinanceInvoice{} = invoice ->
        today = GymClock.today()

        due_date =
          case params["due_date"] do
            nil -> invoice.due_date
            d when is_binary(d) -> Date.from_iso8601!(d)
            d -> d
          end

        auto_status =
          if invoice.status == "overdue" and due_date != nil and
               Date.compare(due_date, today) != :lt and billable_invoice?(invoice) and
               invoice_balance_due(invoice.id) > 0 do
            "issued"
          else
            nil
          end

        changeset_params =
          params
          |> Map.take(["due_date", "notes"])
          |> then(fn p -> if auto_status, do: Map.put(p, "status", auto_status), else: p end)

        invoice
        |> FinanceInvoice.changeset(changeset_params)
        |> Repo.update()
        |> normalize_result(&normalize_invoice/1)
    end
  end

  @impl true
  def mark_overdue_invoices do
    today = GymClock.today()

    {_, _} =
      tenant_scope(FinanceInvoice)
      |> where([i], i.status == "issued" and not is_nil(i.due_date) and i.due_date < ^today)
      |> where([i], is_nil(i.deleted_at))
      |> where([i], fragment("COALESCE(?->>'document_kind', '') <> 'receipt'", i.params))
      |> Repo.update_all(set: [status: "overdue"])

    FinanceInvoice
    |> tenant_scope()
    |> where([i], i.status == "overdue" and not is_nil(i.due_date) and i.due_date >= ^today)
    |> where([i], is_nil(i.deleted_at))
    |> where([i], fragment("COALESCE(?->>'document_kind', '') <> 'receipt'", i.params))
    |> Repo.all()
    |> Enum.each(fn invoice ->
      if invoice_balance_due(invoice.id) > 0 do
        invoice
        |> FinanceInvoice.changeset(%{status: "issued"})
        |> Repo.update!()
      end
    end)

    :ok
  end

  @impl true
  def list_finance_cleanup_records(params) do
    params = string_key_map(params || %{})
    search = params["q"] || params["search"] || ""
    limit = parse_integer(params["limit"], 50) |> min(100) |> max(1)

    invoice_records =
      FinanceInvoice
      |> where([invoice], is_nil(invoice.deleted_at))
      |> maybe_search_cleanup_invoice(search)
      |> order_by([invoice], desc: invoice.inserted_at)
      |> limit(^limit)
      |> Repo.all()
      |> Enum.map(&cleanup_invoice_record/1)

    payment_records =
      MembershipPayment
      |> where([payment], is_nil(payment.deleted_at))
      |> maybe_search_cleanup_payment(search)
      |> order_by([payment], desc: payment.inserted_at)
      |> limit(^limit)
      |> Repo.all()
      |> Enum.map(&cleanup_payment_record/1)

    (invoice_records ++ payment_records)
    |> Enum.sort_by(& &1.inserted_at, {:desc, DateTime})
    |> Enum.take(limit)
  end

  @impl true
  def soft_delete_finance_record(record_type, record_id, admin_id, params) do
    params = string_key_map(params || %{})

    case normalize_cleanup_record_type(record_type) do
      :invoice -> soft_delete_invoice_record(record_id, admin_id, params)
      :payment -> soft_delete_payment_record(record_id, admin_id, params)
      :unknown -> {:error, :bad_request}
    end
  end

  @impl true
  def create_invoice(membership_id, params) do
    params = string_key_map(params)

    with %Membership{} = membership <- Membership |> tenant_scope() |> Repo.get(membership_id),
         {:ok, params} <- maybe_prefill_invoice_from_subscription(membership.id, params),
         params = apply_member_discount(membership, params),
         :ok <- validate_invoice_subscription_link(membership.id, params),
         {:ok, line_params} <- invoice_line_params(params),
         :ok <- validate_invoice_line_subscription_links(membership.id, line_params),
         totals <- InvoiceLifecycle.invoice_totals(line_params) do
      Repo.transaction(fn ->
        invoice_number = next_invoice_number(line_params)

        invoice =
          %FinanceInvoice{}
          |> FinanceInvoice.changeset(
            params
            |> Map.put("membership_id", membership.id)
            |> Map.put("user_id", membership.user_id)
            |> Map.put_new("invoice_number", invoice_number)
            |> Map.put_new("invoice_type", "manual")
            |> Map.put_new("status", "draft")
            |> Map.put_new("currency", "EUR")
            |> Map.merge(string_key_map(totals))
          )
          |> Repo.insert()
          |> case do
            {:ok, invoice} -> invoice
            {:error, reason} -> Repo.rollback(reason)
          end

        lines =
          Enum.map(line_params, fn line ->
            %FinanceInvoiceLine{}
            |> FinanceInvoiceLine.changeset(Map.put(line, "finance_invoice_id", invoice.id))
            |> Repo.insert()
            |> case do
              {:ok, line} -> line
              {:error, reason} -> Repo.rollback(reason)
            end
          end)

        invoice
        |> normalize_invoice()
        |> Map.put(:lines, Enum.map(lines, &normalize_invoice_line/1))
        |> Map.put(:balance_due_cents, invoice_balance_due(invoice.id))
      end)
    else
      nil -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def generate_renewal_invoice(membership_id, params) do
    params = string_key_map(params)

    with %Membership{} = membership <- Membership |> tenant_scope() |> Repo.get(membership_id),
         %MembershipPackageSubscription{} = subscription <-
           renewal_subscription(membership.id, params["membership_package_subscription_id"]),
         :ok <- not_corporate_seat(subscription),
         :ok <- add_on_base_active(subscription),
         :ok <- SubscriptionSelection.renewable?(subscription.params_snapshot || %{}),
         :ok <- MemberRenewal.renewal_allowed(subscription, membership) do
      period_start = parse_date(params["service_period_start"], GymClock.today())

      with {:ok, {period_start, period_end}} <-
             InvoiceLifecycle.renewal_period(
               subscription.billing_period_snapshot,
               period_start,
               parse_date(params["service_period_end"], nil)
             ) do
        if renewal_invoice_exists?(membership.id, subscription.id, period_start, period_end) do
          {:error, :duplicate_renewal_invoice}
        else
          case renewal_with_referral_discounts(membership, subscription, fn discount_cents ->
                 %{
                   "invoice_type" => "renewal",
                   "membership_package_subscription_id" => subscription.id,
                   "issue_date" => params["issue_date"],
                   "due_date" => params["due_date"] || period_start,
                   "service_period_start" => period_start,
                   "service_period_end" => period_end,
                   "notes" => params["notes"],
                   "lines" => [
                     %{
                       "membership_package_subscription_id" => subscription.id,
                       "line_type" => "membership_package",
                       "description" => "Renewal: #{subscription.package_code_snapshot}",
                       "quantity" => 1,
                       "unit_amount_cents" => subscription.price_cents_snapshot || 0,
                       "discount_cents" => discount_cents,
                       "package_code_snapshot" => subscription.package_code_snapshot,
                       "package_family_snapshot" => subscription.package_family_snapshot
                     }
                   ]
                 }
               end) do
            {:error, %Ecto.Changeset{} = changeset} ->
              if constraint_error?(
                   changeset,
                   "finance_renewal_invoices_period_unique_index"
                 ) do
                {:error, :duplicate_renewal_invoice}
              else
                {:error, changeset}
              end

            result ->
              result
          end
        end
      end
    else
      nil -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  # ADR-156 (board 11 Q6): the member's given discount rewards come off this
  # renewal, each used once. The rewards are locked so two renewals can't
  # both take the same one.
  defp renewal_with_referral_discounts(%Membership{} = membership, subscription, invoice_params) do
    Repo.transaction(fn ->
      renewal_still_allowed!(membership, subscription)

      rewards =
        ReferralReward
        |> tenant_scope()
        |> where(
          [r],
          r.recipient_user_id == ^membership.user_id and r.reward_type == "discount" and
            r.status == "applied" and is_nil(r.renewal_invoice_id)
        )
        |> lock("FOR UPDATE")
        |> Repo.all()

      discount_cents =
        ReferralRewardFulfillment.renewal_discount_cents(
          rewards,
          subscription.price_cents_snapshot || 0
        )

      with {:ok, invoice} <- create_invoice(membership.id, invoice_params.(discount_cents)) do
        reward_ids = Enum.map(rewards, & &1.id)

        ReferralReward
        |> where([r], r.id in ^reward_ids)
        |> Repo.update_all(set: [renewal_invoice_id: invoice.id, updated_at: DateTime.utc_now()])

        invoice
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  # ADR-220: the member may turn renewal off (or leave) while this invoice is
  # being made; both rows are locked in the same order as those changes and
  # the choice is checked again, so no renewal slips past it.
  defp renewal_still_allowed!(membership, subscription) do
    locked_membership =
      Membership |> tenant_scope() |> lock("FOR UPDATE") |> Repo.get(membership.id)

    locked_subscription = locked_subscription(membership.id, subscription.id)

    with %Membership{} <- locked_membership,
         %MembershipPackageSubscription{} <- locked_subscription,
         :ok <- MemberRenewal.renewal_allowed(locked_subscription, locked_membership) do
      :ok
    else
      nil -> Repo.rollback(:not_found)
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  # Voiding a renewal frees the discount rewards it took for the next one.
  defp release_referral_discounts(invoice_id) do
    ReferralReward
    |> tenant_scope()
    |> where([r], r.renewal_invoice_id == ^invoice_id)
    |> Repo.update_all(set: [renewal_invoice_id: nil, updated_at: DateTime.utc_now()])
  end

  @impl true
  def issue_invoice(invoice_id, params) do
    params = string_key_map(params)

    Repo.transaction(fn ->
      case locked_invoice(invoice_id) do
        nil ->
          Repo.rollback(:not_found)

        %FinanceInvoice{status: "void"} ->
          Repo.rollback(:invoice_void)

        %FinanceInvoice{} = invoice ->
          invoice
          |> FinanceInvoice.changeset(%{
            status: "issued",
            issue_date: params["issue_date"] || invoice.issue_date || GymClock.today(),
            due_date: params["due_date"] || invoice.due_date || default_invoice_due_date(invoice)
          })
          |> Repo.update()
          |> case do
            {:ok, updated_invoice} ->
              {:ok, refreshed_invoice} = refresh_invoice_status(updated_invoice.id)
              refresh_entitlement_snapshot(updated_invoice.membership_id)
              normalize_invoice_with_balance(refreshed_invoice)

            {:error, reason} ->
              Repo.rollback(reason)
          end
      end
    end)
  end

  @impl true
  def void_invoice(invoice_id, params) do
    params = string_key_map(params)

    Repo.transaction(fn ->
      case locked_invoice(invoice_id) do
        nil ->
          Repo.rollback(:not_found)

        %FinanceInvoice{} = invoice ->
          with :ok <-
                 InvoiceLifecycle.validate_void(
                   invoice.status,
                   invoice_paid_cents(invoice.id),
                   invoice_credit_applied_cents(invoice.id)
                 ) do
            invoice
            |> FinanceInvoice.changeset(%{
              status: "void",
              voided_at: params["voided_at"] || utc_now(),
              notes: params["notes"] || invoice.notes
            })
            |> Repo.update()
            |> case do
              {:ok, updated_invoice} ->
                release_referral_discounts(updated_invoice.id)
                refresh_entitlement_snapshot(updated_invoice.membership_id)
                normalize_invoice_with_balance(updated_invoice)

              {:error, reason} ->
                Repo.rollback(reason)
            end
          else
            {:error, reason} -> Repo.rollback(reason)
          end
      end
    end)
  end

  @impl true
  def apply_credit_to_invoice(membership_id, invoice_id, params) do
    params = string_key_map(params)

    Repo.transaction(fn ->
      with %Membership{} = membership <- locked_membership(membership_id),
           %FinanceInvoice{} = invoice <- locked_invoice(invoice_id),
           :ok <- require_request_id(params),
           :ok <-
             MembershipLinks.validate_optional_link(
               :finance_invoice_id,
               membership.id,
               invoice.membership_id
             ),
           amount_cents <- parse_integer(params["amount_cents"], 0),
           available_cents <- credit_balance(membership.id),
           remaining_due_cents <- invoice_balance_due(invoice.id),
           :ok <-
             InvoiceLifecycle.validate_credit_application(
               invoice.status,
               available_cents,
               amount_cents,
               remaining_due_cents
             ),
           {:ok, entry} <-
             create_credit_entry(%{
               "membership_id" => membership.id,
               "user_id" => membership.user_id,
               "finance_invoice_id" => invoice.id,
               "source_type" => "invoice_offset",
               "entry_type" => "invoice_offset",
               "amount_cents" => -amount_cents,
               "currency" => invoice.currency || "EUR",
               "occurred_on" => GymClock.today(),
               "occurred_at" => utc_now(),
               "description" => params["description"] || params["notes"],
               "created_by_id" => params["created_by_id"],
               "idempotency_key" =>
                 scoped_idempotency_key("invoice_offset:#{invoice.id}", membership.id, params),
               "params" => credit_application_params(params)
             }) do
        refresh_invoice_and_entitlement(invoice.id, membership.id)
        entry
      else
        nil -> Repo.rollback(:not_found)
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  @impl true
  def get_entitlement(user_id) do
    case tenant_scope(Membership)
         |> where([membership], membership.user_id == ^user_id)
         |> Repo.one() do
      nil -> nil
      %Membership{} = membership -> entitlement_for_membership(membership)
    end
  end

  @impl true
  def get_effective_entitlement(user_id) do
    case tenant_scope(Membership)
         |> where([membership], membership.user_id == ^user_id)
         |> Repo.one() do
      nil -> nil
      %Membership{} = membership -> effective_entitlement(membership, GymClock.today())
    end
  end

  # Read-only: for each booking request, does any of the member's usable
  # subscriptions on that local day include it (scope, not remaining count)?
  @impl true
  def package_coverage(_user_id, []), do: []

  def package_coverage(user_id, requests) do
    case tenant_scope(Membership) |> where([m], m.user_id == ^user_id) |> Repo.one() do
      nil ->
        Enum.map(requests, fn _request -> false end)

      %Membership{} = membership ->
        entitlement = entitlement_for_membership(membership)
        requests = Enum.map(requests, &(&1 |> atom_key_map() |> put_local_start()))

        subscriptions_on =
          requests
          |> Enum.map(&request_date/1)
          |> Enum.uniq()
          |> Map.new(&{&1, effective_subscriptions(membership.id, &1)})

        Enum.map(requests, fn request ->
          Enum.any?(subscriptions_on[request_date(request)], fn subscription ->
            EntitlementPolicy.covers?(
              entitlement,
              subscription.params_snapshot || %{},
              resolve_request_allowance(subscription, request)
            )
          end)
        end)
    end
  end

  defp local_date(%{starts_at: %DateTime{} = starts_at}) do
    timezone = GymClock.zone() || "Etc/UTC"

    case DateTime.shift_zone(starts_at, timezone) do
      {:ok, local} -> DateTime.to_date(local)
      _error -> DateTime.to_date(starts_at)
    end
  end

  # ADR-176/179: the day a request draws on is the gym-local day of the
  # session it books (a 00:30 class belongs to the gym's day, not UTC's);
  # without a session, the given day, else the gym's today.
  defp request_date(%{starts_at: %DateTime{}} = request), do: local_date(request)
  defp request_date(request), do: Map.get(request, :occurred_on) || GymClock.today()

  @impl true
  def reserve_entitlement(user_id, request) do
    request = atom_key_map(request)

    result =
      Repo.transaction(fn ->
        idempotency_key = Map.fetch!(request, :idempotency_key)

        case tenant_scope(FinanceEntitlementUsageEntry)
             |> where([entry], entry.idempotency_key == ^idempotency_key)
             |> Repo.one() do
          %FinanceEntitlementUsageEntry{} = existing ->
            normalize_usage_entry(existing)

          nil ->
            case Repo.one(
                   from m in tenant_scope(Membership),
                     where: m.user_id == ^user_id,
                     lock: "FOR UPDATE"
                 ) do
              nil -> authorize_missing_profile!(request)
              %Membership{} = membership -> reserve_for_membership!(membership, request)
            end
        end
      end)

    case result do
      {:error, {reason, details}} -> {:error, reason, details}
      other -> other
    end
  end

  @impl true
  def finalize_entitlement(reservation_id, params) do
    transition_entitlement(reservation_id, params, "finalize", 0)
  end

  @impl true
  def release_entitlement(reservation_id, params) do
    transition_entitlement(reservation_id, params, "release", :reverse)
  end

  @impl true
  def grant_allowance(user_id, admin_id, params) do
    params = atom_key_map(params)

    Repo.transaction(fn ->
      membership =
        Repo.one(
          from m in tenant_scope(Membership), where: m.user_id == ^user_id, lock: "FOR UPDATE"
        ) ||
          Repo.rollback(:finance_profile_missing)

      occurred_on = Map.get(params, :occurred_on, GymClock.today())
      allowance = Map.get(params, :allowance)
      candidates = effective_subscriptions(membership.id, occurred_on)
      if candidates == [], do: Repo.rollback(:finance_entitlement_inactive)

      # ADR-096: with stacked subscriptions the grant extends the first one
      # whose contract contains the allowance (per-class-type keys included).
      subscription =
        Enum.find(candidates, List.first(candidates), fn candidate ->
          case EntitlementPlan.parse(candidate.params_snapshot || %{}) do
            {:ok, plan} -> Map.has_key?(plan.allowances, allowance)
            _ -> false
          end
        end)

      with {:ok, plan} <- EntitlementPlan.parse(subscription.params_snapshot || %{}),
           %{period: package_period} <- Map.get(plan.allowances, allowance) do
        period = Map.get(params, :period, package_period)
        {period_start, period_end} = AllowancePeriod.bounds(period, occurred_on, subscription)
        quantity = Map.get(params, :quantity, 0)
        reason = Map.get(params, :reason)

        if not (is_integer(quantity) and quantity > 0 and is_binary(reason) and
                  String.trim(reason) != "") do
          Repo.rollback(:invalid_allowance_grant)
        end

        insert_usage_entry!(%{
          membership_id: membership.id,
          membership_package_subscription_id: subscription.id,
          allowance_key: to_string(allowance),
          event_type: "adjustment",
          quantity_delta: -quantity,
          period_start: period_start,
          period_end: period_end,
          source_context: "admin",
          admin_id: admin_id,
          reason: reason,
          idempotency_key: Map.fetch!(params, :idempotency_key),
          metadata: Map.get(params, :metadata, %{})
        })
      else
        nil -> Repo.rollback(:finance_allowance_not_included)
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  # ── Phase B: freezes, booking terms, expiry reminders (ADR-097) ──────────

  @impl true
  def create_freeze(user_id, admin_id, params) do
    params = string_key_map(params)

    Repo.transaction(fn ->
      membership =
        Repo.one(
          from m in tenant_scope(Membership), where: m.user_id == ^user_id, lock: "FOR UPDATE"
        ) || Repo.rollback(:finance_profile_missing)

      today = GymClock.today()
      starts_on = parse_date(params["starts_on"], today)
      ends_on = parse_date(params["ends_on"], nil) || Repo.rollback(:invalid_freeze_dates)

      subscription =
        effective_subscription(membership.id, starts_on) ||
          Repo.rollback(:finance_entitlement_inactive)

      terms = package_terms(subscription.params_snapshot)

      used =
        FinanceSubscriptionFreeze
        |> tenant_scope()
        |> where([freeze], freeze.membership_package_subscription_id == ^subscription.id)
        |> where([freeze], is_nil(freeze.cancelled_at))
        |> Repo.all()
        |> Enum.map(&{&1.starts_on, &1.ends_on})

      %{days: days} =
        case SubscriptionTerms.validate_freeze(
               starts_on,
               ends_on,
               terms[:freeze_days_per_year],
               used,
               today
             ) do
          {:ok, result} -> result
          {:error, reason} -> Repo.rollback(reason)
        end

      extension_days = if subscription.ends_on, do: days, else: 0

      freeze =
        %FinanceSubscriptionFreeze{}
        |> FinanceSubscriptionFreeze.changeset(%{
          membership_id: membership.id,
          membership_package_subscription_id: subscription.id,
          starts_on: starts_on,
          ends_on: ends_on,
          extension_days: extension_days,
          reason: params["reason"],
          admin_id: admin_id
        })
        |> Repo.insert()
        |> case do
          {:ok, freeze} -> freeze
          {:error, reason} -> Repo.rollback(reason)
        end

      shift_subscription_end!(subscription, extension_days)
      refresh_entitlement_snapshot(membership.id)
      normalize_freeze(freeze)
    end)
  end

  @impl true
  def cancel_freeze(user_id, freeze_id, params) do
    params = string_key_map(params)

    Repo.transaction(fn ->
      membership =
        Repo.one(
          from m in tenant_scope(Membership), where: m.user_id == ^user_id, lock: "FOR UPDATE"
        ) || Repo.rollback(:finance_profile_missing)

      freeze =
        FinanceSubscriptionFreeze
        |> tenant_scope()
        |> where([freeze], freeze.id == ^freeze_id and freeze.membership_id == ^membership.id)
        |> lock("FOR UPDATE")
        |> Repo.one() || Repo.rollback(:not_found)

      if freeze.cancelled_at, do: Repo.rollback(:freeze_already_cancelled)

      today = GymClock.today()

      # Unused freeze days are given back: the freeze ends yesterday (or is
      # removed entirely when it has not started) and the extension shrinks.
      {new_ends_on, unused} =
        cond do
          Date.compare(freeze.starts_on, today) != :lt ->
            {freeze.starts_on, SubscriptionTerms.days(freeze.starts_on, freeze.ends_on)}

          Date.compare(freeze.ends_on, today) == :lt ->
            {freeze.ends_on, 0}

          true ->
            {Date.add(today, -1), SubscriptionTerms.days(today, freeze.ends_on)}
        end

      returned = min(unused, freeze.extension_days)

      updated =
        freeze
        |> FinanceSubscriptionFreeze.cancel_changeset(%{
          cancelled_at: DateTime.utc_now(),
          cancel_reason: params["reason"],
          ends_on: new_ends_on,
          extension_days: freeze.extension_days - returned
        })
        |> Repo.update()
        |> case do
          {:ok, freeze} -> freeze
          {:error, reason} -> Repo.rollback(reason)
        end

      subscription =
        MembershipPackageSubscription |> Repo.get!(freeze.membership_package_subscription_id)

      shift_subscription_end!(subscription, -returned)
      refresh_entitlement_snapshot(membership.id)
      normalize_freeze(updated)
    end)
  end

  @impl true
  def list_freezes(user_id) do
    case tenant_scope(Membership) |> where([m], m.user_id == ^user_id) |> Repo.one() do
      nil ->
        []

      membership ->
        FinanceSubscriptionFreeze
        |> tenant_scope()
        |> where([freeze], freeze.membership_id == ^membership.id)
        |> order_by([freeze], desc: freeze.starts_on)
        |> Repo.all()
        |> Enum.map(&normalize_freeze/1)
    end
  end

  # ── Shared memberships (ADR-098) ─────────────────────────────────────────

  @impl true
  def list_beneficiaries(subscription_id) do
    FinanceSubscriptionBeneficiary
    |> tenant_scope()
    |> where([beneficiary], beneficiary.membership_package_subscription_id == ^subscription_id)
    |> where([beneficiary], is_nil(beneficiary.removed_at))
    |> join(:inner, [beneficiary], membership in Membership,
      on: membership.id == beneficiary.membership_id
    )
    |> order_by([beneficiary], asc: beneficiary.inserted_at)
    |> select([beneficiary, membership], {beneficiary, membership.user_id})
    |> Repo.all()
    |> Enum.map(fn {beneficiary, user_id} -> normalize_beneficiary(beneficiary, user_id) end)
  end

  @impl true
  def add_beneficiary(subscription_id, beneficiary_user_id, admin_id, params) do
    params = string_key_map(params)

    Repo.transaction(fn ->
      subscription = locked_subscription!(subscription_id)
      payer = Repo.get!(Membership, subscription.membership_id)

      if payer.user_id == beneficiary_user_id, do: Repo.rollback(:beneficiary_is_payer)

      if PaymentModelPolicy.package_type(subscription) != "shared",
        do: Repo.rollback(:not_a_shared_membership)

      is_minor = params["is_minor"] in [true, "true"]
      active = list_beneficiaries(subscription.id)

      case PaymentModelPolicy.can_add_beneficiary?(
             package_terms(subscription.params_snapshot),
             length(active),
             is_minor
           ) do
        :ok -> :ok
        {:error, reason} -> Repo.rollback(reason)
      end

      membership = ensure_member_membership!(beneficiary_user_id)

      beneficiary =
        %{
          membership_package_subscription_id: subscription.id,
          membership_id: membership.id,
          is_minor: is_minor,
          added_by_id: admin_id
        }
        |> FinanceSubscriptionBeneficiary.changeset()
        |> Repo.insert()
        |> case do
          {:ok, beneficiary} -> beneficiary
          {:error, changeset} -> Repo.rollback(changeset)
        end

      refresh_entitlement_snapshot(membership.id)
      normalize_beneficiary(beneficiary, beneficiary_user_id)
    end)
  end

  @impl true
  def remove_beneficiary(subscription_id, beneficiary_id) do
    Repo.transaction(fn ->
      beneficiary =
        FinanceSubscriptionBeneficiary
        |> tenant_scope()
        |> where(
          [beneficiary],
          beneficiary.id == ^beneficiary_id and
            beneficiary.membership_package_subscription_id == ^subscription_id and
            is_nil(beneficiary.removed_at)
        )
        |> Repo.one() || Repo.rollback(:not_found)

      {:ok, removed} =
        beneficiary
        |> FinanceSubscriptionBeneficiary.remove_changeset(DateTime.utc_now())
        |> Repo.update()

      refresh_entitlement_snapshot(removed.membership_id)
      user_id = Repo.get!(Membership, removed.membership_id).user_id
      normalize_beneficiary(removed, user_id)
    end)
  end

  defp locked_subscription!(subscription_id) do
    MembershipPackageSubscription
    |> tenant_scope()
    |> where([subscription], subscription.id == ^subscription_id)
    |> lock("FOR UPDATE")
    |> Repo.one() || Repo.rollback(:not_found)
  end

  # Beneficiaries and corporate employees need a finance profile; one is
  # created as an active member profile when missing.
  defp ensure_member_membership!(user_id) do
    case tenant_scope(Membership) |> where([m], m.user_id == ^user_id) |> Repo.one() do
      %Membership{} = membership ->
        membership

      nil ->
        %Membership{}
        |> Membership.changeset(%{
          "user_id" => user_id,
          "status" => "active",
          "user_type_snapshot" => "member",
          "signup_source" => "admin_created"
        })
        |> Repo.insert()
        |> case do
          {:ok, membership} -> membership
          {:error, reason} -> Repo.rollback(reason)
        end
    end
  end

  defp normalize_beneficiary(beneficiary, user_id) do
    %{
      id: beneficiary.id,
      subscription_id: beneficiary.membership_package_subscription_id,
      membership_id: beneficiary.membership_id,
      user_id: user_id,
      is_minor: beneficiary.is_minor,
      added_by_id: beneficiary.added_by_id,
      removed_at: beneficiary.removed_at,
      inserted_at: beneficiary.inserted_at
    }
  end

  # ── Corporate clients (ADR-098) ──────────────────────────────────────────

  @impl true
  def list_corporate_clients do
    FinanceCorporateClient
    |> tenant_scope()
    |> order_by([client], asc: client.company_name)
    |> Repo.all()
    |> Enum.map(&normalize_corporate_client/1)
  end

  @impl true
  def get_corporate_client(id) do
    case fetch_corporate_client(id) do
      nil -> nil
      client -> normalize_corporate_client(client)
    end
  end

  @impl true
  def find_corporate_client(%{enrollment_code: code}) when is_binary(code) do
    FinanceCorporateClient
    |> tenant_scope()
    |> where([client], client.enrollment_code == ^String.upcase(String.trim(code)))
    |> where([client], client.status == "active")
    |> Repo.one()
    |> then(&(&1 && normalize_corporate_client(&1)))
  end

  def find_corporate_client(%{email: email}) when is_binary(email) do
    FinanceCorporateClient
    |> tenant_scope()
    |> where([client], client.status == "active")
    |> Repo.all()
    |> Enum.map(&normalize_corporate_client/1)
    |> Enum.find(fn client ->
      client.enrollment == "email_domain" and
        PaymentModelPolicy.email_in_domain?(email, client.enrollment_domain)
    end)
  end

  def find_corporate_client(_criteria), do: nil

  @impl true
  def create_corporate_client(params) do
    params = string_key_map(params)

    Repo.transaction(fn ->
      package =
        tenant_scope(MembershipPackage)
        |> where([package], package.id == ^params["membership_package_id"])
        |> Repo.one() || Repo.rollback(:not_found)

      if PackageContract.type_from_params(package.params) != "corporate",
        do: Repo.rollback(:not_a_corporate_package)

      params
      |> Map.put("enrollment_code", params["enrollment_code"] || enrollment_code())
      |> FinanceCorporateClient.create_changeset()
      |> Repo.insert()
      |> case do
        {:ok, client} -> normalize_corporate_client(client)
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
  end

  @impl true
  def update_corporate_client(id, params) do
    params = string_key_map(params)

    params =
      if params["regenerate_code"] in [true, "true"],
        do: Map.put(params, "enrollment_code", enrollment_code()),
        else: Map.delete(params, "enrollment_code")

    case fetch_corporate_client(id) do
      nil ->
        {:error, :not_found}

      client ->
        client
        |> FinanceCorporateClient.update_changeset(params)
        |> Repo.update()
        |> case do
          {:ok, client} -> {:ok, normalize_corporate_client(client)}
          error -> error
        end
    end
  end

  @impl true
  def enroll_corporate_seat(client_id, user_id, params) do
    Repo.transaction(fn ->
      client =
        FinanceCorporateClient
        |> tenant_scope()
        |> where([client], client.id == ^client_id and client.status == "active")
        |> lock("FOR UPDATE")
        |> Repo.one() || Repo.rollback(:not_found)

      package = Repo.get!(MembershipPackage, client.membership_package_id)
      terms = package_terms(package.params)
      membership = ensure_member_membership!(user_id)
      seats = active_corporate_seats(client.id, GymClock.today())

      if Enum.any?(seats, &(&1.membership_id == membership.id)),
        do: Repo.rollback(:already_enrolled)

      unless PaymentModelPolicy.seat_available?(terms[:seats], length(seats)),
        do: Repo.rollback(:corporate_seats_full)

      params =
        params
        |> string_key_map()
        |> Map.take(["starts_on", "corporate_enrolled_via"])
        |> Map.put("corporate_client_id", client.id)

      subscription = insert_subscription!(membership, package, params)
      refresh_entitlement_snapshot(membership.id)
      normalize_subscription(subscription)
    end)
  end

  @impl true
  def end_corporate_seat(client_id, subscription_id) do
    Repo.transaction(fn ->
      subscription =
        MembershipPackageSubscription
        |> tenant_scope()
        |> where(
          [subscription],
          subscription.id == ^subscription_id and subscription.corporate_client_id == ^client_id
        )
        |> lock("FOR UPDATE")
        |> Repo.one() || Repo.rollback(:not_found)

      {:ok, ended} =
        subscription
        |> MembershipPackageSubscription.changeset(%{
          "status" => "cancelled",
          "ends_on" => GymClock.today()
        })
        |> Repo.update()

      refresh_entitlement_snapshot(ended.membership_id)
      normalize_subscription(ended)
    end)
  end

  @impl true
  def end_email_domain_seats(user_ids, email) when is_list(user_ids) do
    Repo.transaction(fn ->
      MembershipPackageSubscription
      |> tenant_scope()
      |> join(:inner, [subscription], membership in Membership,
        on: membership.id == subscription.membership_id
      )
      |> where([subscription, membership], membership.user_id in ^user_ids)
      |> where([subscription], subscription.corporate_enrolled_via == "email_domain")
      |> where([subscription], subscription.status == "active")
      |> lock("FOR UPDATE")
      |> Repo.all()
      |> Enum.reject(fn subscription ->
        client = fetch_corporate_client(subscription.corporate_client_id)
        terms = client && corporate_client_terms(client)

        PaymentModelPolicy.email_in_domain?(email, terms && terms[:enrollment_domain])
      end)
      |> Enum.map(fn subscription ->
        {:ok, ended} =
          subscription
          |> MembershipPackageSubscription.changeset(%{
            "status" => "cancelled",
            "ends_on" => GymClock.today()
          })
          |> Repo.update()

        refresh_entitlement_snapshot(ended.membership_id)
        normalize_subscription(ended)
      end)
    end)
  end

  defp corporate_client_terms(client) do
    package = Repo.get(MembershipPackage, client.membership_package_id)
    package_terms(package && package.params)
  end

  @impl true
  def list_corporate_seats(client_id) do
    MembershipPackageSubscription
    |> tenant_scope()
    |> where([subscription], subscription.corporate_client_id == ^client_id)
    |> join(:inner, [subscription], membership in Membership,
      on: membership.id == subscription.membership_id
    )
    |> order_by([subscription], desc: subscription.inserted_at)
    |> select([subscription, membership], {subscription, membership.user_id})
    |> Repo.all()
    |> Enum.map(fn {subscription, user_id} ->
      subscription |> normalize_subscription() |> Map.put(:user_id, user_id)
    end)
  end

  defp active_corporate_seats(client_id, on) do
    MembershipPackageSubscription
    |> tenant_scope()
    |> where([subscription], subscription.corporate_client_id == ^client_id)
    |> where([subscription], subscription.status == "active")
    |> where([subscription], is_nil(subscription.ends_on) or subscription.ends_on >= ^on)
    |> Repo.all()
  end

  # Seats held at any time in the period count as used.
  defp used_corporate_seats(client_id, period_start, period_end) do
    MembershipPackageSubscription
    |> tenant_scope()
    |> where([subscription], subscription.corporate_client_id == ^client_id)
    |> where([subscription], subscription.starts_on <= ^period_end)
    |> where(
      [subscription],
      is_nil(subscription.ends_on) or subscription.ends_on >= ^period_start
    )
    |> select([subscription], count(subscription.membership_id, :distinct))
    |> Repo.one()
  end

  @impl true
  def generate_corporate_invoice(client_id, %Date{} = on) do
    Repo.transaction(fn ->
      client = fetch_corporate_client(client_id) || Repo.rollback(:not_found)
      package = Repo.get!(MembershipPackage, client.membership_package_id)
      period = PaymentModelPolicy.corporate_period(package.billing_period, on)

      case insert_corporate_invoice(client, package, period, GymClock.today()) do
        {:ok, invoice} -> invoice_with_payments(invoice)
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
  end

  # ADR-098: the daily run issues each auto-invoicing client's due period once;
  # the unique period index makes a repeated run a no-op.
  @impl true
  def issue_due_corporate_invoices(%Date{} = today) do
    FinanceCorporateClient
    |> tenant_scope()
    |> where([client], client.status == "active" and client.auto_invoice)
    |> Repo.all()
    |> Enum.flat_map(fn client ->
      package = Repo.get!(MembershipPackage, client.membership_package_id)
      seat_billing = package_terms(package.params)[:seat_billing] || "agreed"
      client_since = DateTime.to_date(client.inserted_at)

      with {:ok, {period_start, _end} = period} <-
             CorporateInvoicePolicy.period_to_invoice(
               package.billing_period,
               seat_billing,
               client_since,
               today
             ),
           false <- corporate_period_invoiced?(client.id, period_start),
           {:ok, invoice} <-
             Repo.transaction(fn ->
               case insert_corporate_invoice(client, package, period, today) do
                 {:ok, invoice} -> invoice
                 {:error, changeset} -> Repo.rollback(changeset)
               end
             end) do
        [
          invoice
          |> invoice_with_payments()
          |> Map.put(:client, normalize_corporate_client(client))
        ]
      else
        _skip -> []
      end
    end)
  end

  defp corporate_period_invoiced?(client_id, period_start) do
    FinanceCorporateInvoice
    |> tenant_scope()
    |> where([i], i.corporate_client_id == ^client_id and i.period_start == ^period_start)
    |> Repo.exists?()
  end

  defp insert_corporate_invoice(client, package, {period_start, period_end}, issued_on) do
    terms = package_terms(package.params)
    seat_billing = terms[:seat_billing] || "agreed"
    used = used_corporate_seats(client.id, period_start, period_end)
    seats = PaymentModelPolicy.seats_billed(seat_billing, terms[:seats], used)

    %{
      corporate_client_id: client.id,
      invoice_number: InvoiceNumber.format(next_invoice_sequence(), DateTime.utc_now(), "CORP"),
      period_start: period_start,
      period_end: period_end,
      seat_billing: seat_billing,
      seats_billed: seats,
      unit_price_cents: package.base_price_cents,
      total_cents: seats * package.base_price_cents,
      issued_on: issued_on,
      due_on: CorporateInvoicePolicy.due_on(issued_on, client.payment_terms_days)
    }
    |> FinanceCorporateInvoice.changeset()
    |> Repo.insert()
  end

  @impl true
  def list_corporate_invoices(client_id) do
    invoices =
      FinanceCorporateInvoice
      |> tenant_scope()
      |> where([invoice], invoice.corporate_client_id == ^client_id)
      |> order_by([invoice], desc: invoice.period_start)
      |> Repo.all()

    payments = corporate_payments_by_invoice(Enum.map(invoices, & &1.id))
    Enum.map(invoices, &normalize_corporate_invoice(&1, Map.get(payments, &1.id, [])))
  end

  @impl true
  def get_corporate_invoice(invoice_id) do
    case fetch_corporate_invoice(invoice_id) do
      nil ->
        nil

      invoice ->
        client = fetch_corporate_client(invoice.corporate_client_id)

        invoice
        |> invoice_with_payments()
        |> Map.put(:client, client && normalize_corporate_client(client))
    end
  end

  @impl true
  def record_corporate_payment(invoice_id, admin_id, params) do
    params = string_key_map(params)

    Repo.transaction(fn ->
      invoice = locked_corporate_invoice!(invoice_id)
      paid = corporate_paid_cents(invoice.id)
      amount = parse_integer(params["amount_cents"], 0)

      with :ok <-
             CorporateInvoicePolicy.can_record_payment?(
               invoice,
               amount,
               invoice.total_cents - paid
             ),
           {:ok, _payment} <-
             %{
               corporate_invoice_id: invoice.id,
               amount_cents: amount,
               payment_method: params["payment_method"],
               paid_on: parse_date(params["paid_on"], GymClock.today()),
               reference: params["reference"],
               notes: params["notes"],
               recorded_by_id: admin_id
             }
             |> FinanceCorporatePayment.changeset()
             |> Repo.insert() do
        settle_corporate_invoice!(invoice)
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  @impl true
  def reverse_corporate_payment(invoice_id, payment_id, admin_id, params) do
    params = string_key_map(params)

    Repo.transaction(fn ->
      invoice = locked_corporate_invoice!(invoice_id)

      payment =
        FinanceCorporatePayment
        |> tenant_scope()
        |> where([p], p.id == ^payment_id and p.corporate_invoice_id == ^invoice.id)
        |> where([p], is_nil(p.reversed_at))
        |> Repo.one() || Repo.rollback(:not_found)

      if invoice.status == "void", do: Repo.rollback(:corporate_invoice_closed)

      payment
      |> FinanceCorporatePayment.reverse_changeset(
        admin_id,
        params["reason"],
        DateTime.utc_now()
      )
      |> Repo.update()
      |> case do
        {:ok, _payment} -> settle_corporate_invoice!(invoice)
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
  end

  @impl true
  def set_corporate_invoice_status(invoice_id, "void") do
    Repo.transaction(fn ->
      invoice = locked_corporate_invoice!(invoice_id)

      case CorporateInvoicePolicy.can_void?(invoice, corporate_paid_cents(invoice.id)) do
        :ok ->
          invoice
          |> FinanceCorporateInvoice.status_changeset("void", nil)
          |> Repo.update!()
          |> invoice_with_payments()

        {:error, reason} ->
          Repo.rollback(reason)
      end
    end)
  end

  def set_corporate_invoice_status(_invoice_id, _status), do: {:error, :invalid_invoice_status}

  @impl true
  def mark_overdue_corporate_invoices(%Date{} = today) do
    {count, _} =
      FinanceCorporateInvoice
      |> tenant_scope()
      |> where([i], i.status == "issued" and i.due_on < ^today)
      |> Repo.update_all(set: [status: "overdue", updated_at: DateTime.utc_now()])

    count
  end

  @impl true
  def corporate_invoices_needing_reminder(%Date{} = today, interval_days) do
    FinanceCorporateInvoice
    |> tenant_scope()
    |> where([i], i.status == "overdue")
    |> Repo.all()
    |> Enum.filter(&CorporateInvoicePolicy.reminder_due?(&1, today, interval_days))
    |> Enum.map(fn invoice ->
      client = fetch_corporate_client(invoice.corporate_client_id)

      invoice
      |> invoice_with_payments()
      |> Map.put(:client, client && normalize_corporate_client(client))
    end)
  end

  @impl true
  def mark_corporate_invoice_reminded(invoice_id, %Date{} = on) do
    case fetch_corporate_invoice(invoice_id) do
      nil ->
        {:error, :not_found}

      invoice ->
        invoice
        |> FinanceCorporateInvoice.reminded_changeset(on)
        |> Repo.update()
        |> case do
          {:ok, invoice} -> {:ok, invoice_with_payments(invoice)}
          error -> error
        end
    end
  end

  defp fetch_corporate_invoice(id) do
    case Ecto.UUID.cast(id) do
      {:ok, id} -> tenant_scope(FinanceCorporateInvoice) |> where([i], i.id == ^id) |> Repo.one()
      :error -> nil
    end
  end

  defp locked_corporate_invoice!(id) do
    case Ecto.UUID.cast(id) do
      {:ok, id} ->
        FinanceCorporateInvoice
        |> tenant_scope()
        |> where([i], i.id == ^id)
        |> lock("FOR UPDATE")
        |> Repo.one() || Repo.rollback(:not_found)

      :error ->
        Repo.rollback(:not_found)
    end
  end

  # Recomputes the status from the payments still standing and returns the
  # invoice in its API shape.
  defp settle_corporate_invoice!(invoice) do
    paid = corporate_paid_cents(invoice.id)
    today = GymClock.today()
    status = CorporateInvoicePolicy.status_after_payments(invoice, paid, today)

    paid_on =
      if status == "paid",
        do: last_corporate_payment_date(invoice.id) || today

    invoice
    |> FinanceCorporateInvoice.status_changeset(status, paid_on)
    |> Repo.update!()
    |> invoice_with_payments()
  end

  defp corporate_paid_cents(invoice_id) do
    FinanceCorporatePayment
    |> tenant_scope()
    |> where([p], p.corporate_invoice_id == ^invoice_id and is_nil(p.reversed_at))
    |> select([p], coalesce(sum(p.amount_cents), 0))
    |> Repo.one()
    |> to_integer_cents()
  end

  defp last_corporate_payment_date(invoice_id) do
    FinanceCorporatePayment
    |> tenant_scope()
    |> where([p], p.corporate_invoice_id == ^invoice_id and is_nil(p.reversed_at))
    |> select([p], max(p.paid_on))
    |> Repo.one()
  end

  defp corporate_payments_by_invoice([]), do: %{}

  defp corporate_payments_by_invoice(invoice_ids) do
    FinanceCorporatePayment
    |> tenant_scope()
    |> where([p], p.corporate_invoice_id in ^invoice_ids)
    |> order_by([p], asc: p.paid_on, asc: p.inserted_at)
    |> Repo.all()
    |> Enum.group_by(& &1.corporate_invoice_id)
  end

  defp invoice_with_payments(invoice) do
    payments = Map.get(corporate_payments_by_invoice([invoice.id]), invoice.id, [])
    normalize_corporate_invoice(invoice, payments)
  end

  defp fetch_corporate_client(id) do
    case Ecto.UUID.cast(id) do
      {:ok, id} -> tenant_scope(FinanceCorporateClient) |> where([c], c.id == ^id) |> Repo.one()
      :error -> nil
    end
  end

  @code_alphabet ~c"ABCDEFGHJKLMNPQRSTUVWXYZ23456789"

  defp enrollment_code do
    for _ <- 1..8, into: "", do: <<Enum.random(@code_alphabet)>>
  end

  defp normalize_corporate_client(client) do
    package = Repo.get(MembershipPackage, client.membership_package_id)
    terms = package_terms(package && package.params)

    %{
      id: client.id,
      membership_package_id: client.membership_package_id,
      package_name: package && package.name,
      company_name: client.company_name,
      billing_email: client.billing_email,
      contact_name: client.contact_name,
      enrollment_code: client.enrollment_code,
      enrollment: terms[:enrollment] || "invite_code",
      enrollment_domain: terms[:enrollment_domain],
      seats: terms[:seats],
      seat_billing: terms[:seat_billing] || "agreed",
      active_seats: length(active_corporate_seats(client.id, GymClock.today())),
      payment_terms_days: client.payment_terms_days,
      auto_invoice: client.auto_invoice,
      status: client.status
    }
  end

  defp normalize_corporate_invoice(invoice, payments) do
    paid = payments |> Enum.reject(& &1.reversed_at) |> Enum.map(& &1.amount_cents) |> Enum.sum()

    invoice
    |> Map.take([
      :id,
      :corporate_client_id,
      :invoice_number,
      :period_start,
      :period_end,
      :seat_billing,
      :seats_billed,
      :unit_price_cents,
      :total_cents,
      :status,
      :issued_on,
      :due_on,
      :paid_on,
      :last_reminded_on,
      :reminder_count
    ])
    |> Map.merge(%{
      paid_cents: paid,
      balance_cents: if(invoice.status == "void", do: 0, else: invoice.total_cents - paid),
      payments: Enum.map(payments, &normalize_corporate_payment/1)
    })
  end

  defp normalize_corporate_payment(payment) do
    Map.take(payment, [
      :id,
      :amount_cents,
      :payment_method,
      :paid_on,
      :reference,
      :notes,
      :recorded_by_id,
      :reversed_at,
      :reversal_reason,
      :inserted_at
    ])
  end

  @impl true
  def allowance_terms(user_id, allowance, occurred_on) do
    with %Membership{} = membership <-
           tenant_scope(Membership) |> where([m], m.user_id == ^user_id) |> Repo.one() do
      membership.id
      |> effective_subscriptions(occurred_on)
      |> Enum.find_value(fn subscription ->
        case EntitlementPlan.parse(subscription.params_snapshot || %{}) do
          {:ok, %{allowances: allowances} = plan} when is_map_key(allowances, allowance) ->
            plan.terms

          _other ->
            nil
        end
      end)
    else
      _missing -> nil
    end
  end

  @impl true
  def booking_terms(user_id, occurred_on) do
    with %Membership{} = membership <-
           tenant_scope(Membership) |> where([m], m.user_id == ^user_id) |> Repo.one(),
         %MembershipPackageSubscription{} = subscription <-
           effective_subscription(membership.id, occurred_on) do
      terms = package_terms(subscription.params_snapshot)

      Map.take(terms, [
        :booking_window_days,
        :cancellation_cutoff_hours,
        :waitlist_priority,
        :no_show_penalty_waived
      ])
    else
      _ ->
        %{
          booking_window_days: nil,
          cancellation_cutoff_hours: nil,
          waitlist_priority: "normal",
          no_show_penalty_waived: false
        }
    end
  end

  @impl true
  def subscriptions_due_for_expiry_reminder(%Date{} = today) do
    MembershipPackageSubscription
    |> tenant_scope()
    |> where([subscription], subscription.status == "active")
    |> where([subscription], subscription.ends_on >= ^today)
    |> where([subscription], subscription.ends_on <= ^Date.add(today, 30))
    |> join(:inner, [subscription], membership in Membership,
      on: membership.id == subscription.membership_id
    )
    # ADR-220: someone leaving the box is not asked to renew.
    |> where([_subscription, membership], is_nil(membership.left_at))
    |> select([subscription, membership], {subscription, membership.user_id})
    |> Repo.all()
    |> Enum.flat_map(fn {subscription, user_id} ->
      days = package_terms(subscription.params_snapshot)[:expiry_reminder_days] || 0

      if days > 0 and Date.diff(subscription.ends_on, today) == days do
        [
          %{
            user_id: user_id,
            subscription_id: subscription.id,
            package_name: package_name(subscription),
            ends_on: subscription.ends_on,
            days: days
          }
        ]
      else
        []
      end
    end)
  end

  defp package_name(subscription) do
    case MembershipPackage |> tenant_scope() |> Repo.get(subscription.membership_package_id) do
      nil -> subscription.package_code_snapshot
      package -> package.name
    end
  end

  defp shift_subscription_end!(_subscription, 0), do: :ok
  defp shift_subscription_end!(%{ends_on: nil}, _days), do: :ok

  defp shift_subscription_end!(subscription, days) do
    subscription
    |> MembershipPackageSubscription.changeset(%{ends_on: Date.add(subscription.ends_on, days)})
    |> Repo.update()
    |> case do
      {:ok, _} -> :ok
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp normalize_freeze(freeze) do
    %{
      id: freeze.id,
      membership_id: freeze.membership_id,
      membership_package_subscription_id: freeze.membership_package_subscription_id,
      starts_on: freeze.starts_on,
      ends_on: freeze.ends_on,
      extension_days: freeze.extension_days,
      reason: freeze.reason,
      admin_id: freeze.admin_id,
      cancelled_at: freeze.cancelled_at,
      cancel_reason: freeze.cancel_reason,
      inserted_at: freeze.inserted_at
    }
  end

  @impl true
  def revoke_allowance_grant(user_id, admin_id, grant_id, params) do
    params = atom_key_map(params)

    Repo.transaction(fn ->
      grant =
        from(entry in tenant_scope(FinanceEntitlementUsageEntry),
          join: membership in Membership,
          on: membership.id == entry.membership_id,
          where: entry.id == ^grant_id and membership.user_id == ^user_id,
          lock: "FOR UPDATE"
        )
        |> Repo.one()
        |> case do
          nil -> Repo.rollback(:not_found)
          entry -> entry
        end

      if grant.event_type != "adjustment" or grant.quantity_delta >= 0,
        do: Repo.rollback(:invalid_allowance_grant)

      if Repo.exists?(
           from child in FinanceEntitlementUsageEntry,
             where: child.parent_entry_id == ^grant.id and child.event_type == "adjustment"
         ),
         do: Repo.rollback(:allowance_grant_already_revoked)

      reason = Map.get(params, :reason)

      if not (is_binary(reason) and String.trim(reason) != ""),
        do: Repo.rollback(:invalid_allowance_grant)

      insert_usage_entry!(%{
        membership_id: grant.membership_id,
        membership_package_subscription_id: grant.membership_package_subscription_id,
        allowance_key: grant.allowance_key,
        event_type: "adjustment",
        quantity_delta: -grant.quantity_delta,
        period_start: grant.period_start,
        period_end: grant.period_end,
        source_context: "admin",
        parent_entry_id: grant.id,
        admin_id: admin_id,
        reason: reason,
        idempotency_key: Map.fetch!(params, :idempotency_key),
        metadata: Map.get(params, :metadata, %{})
      })
    end)
  end

  @impl true
  def release_stale_entitlement_reservations(cutoff) do
    reservations =
      from(entry in tenant_scope(FinanceEntitlementUsageEntry), as: :entry)
      |> where([entry], entry.event_type == "reserve" and entry.inserted_at < ^cutoff)
      |> where(
        [entry],
        not exists(
          from child in FinanceEntitlementUsageEntry,
            where: child.parent_entry_id == parent_as(:entry).id,
            where: child.event_type in ["finalize", "release"],
            select: 1
        )
      )
      |> Repo.all()

    Enum.reduce_while(reservations, {:ok, 0}, fn reservation, {:ok, count} ->
      case release_entitlement(reservation.id, %{
             idempotency_key: "stale-entitlement-reservation:#{reservation.id}",
             reason: "automatic stale reservation reconciliation"
           }) do
        {:ok, _entry} -> {:cont, {:ok, count + 1}}
        {:error, :entitlement_reservation_already_closed} -> {:cont, {:ok, count}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  @impl true
  def transition_entitlement_source(
        user_id,
        source_context,
        source_id,
        allowance,
        transition,
        params
      ) do
    params = atom_key_map(params)

    reservation =
      from(entry in FinanceEntitlementUsageEntry, as: :entry)
      |> join(:inner, [entry], membership in Membership, on: membership.id == entry.membership_id)
      |> where([entry, membership], membership.user_id == ^user_id)
      |> where([entry], entry.source_context == ^to_string(source_context))
      |> where([entry], entry.source_id == ^source_id)
      |> where_allowance_key(allowance)
      |> where([entry], entry.event_type == "reserve")
      |> where(
        [entry],
        not exists(
          from child in FinanceEntitlementUsageEntry,
            where: child.parent_entry_id == parent_as(:entry).id,
            where: child.event_type in ["finalize", "release"],
            select: 1
        )
      )
      |> order_by([entry], desc: entry.inserted_at)
      |> limit(1)
      |> Repo.one()

    case reservation do
      nil -> {:ok, %{transition: :not_required}}
      entry when transition == :finalize -> finalize_entitlement(entry.id, params)
      entry when transition == :release -> release_entitlement(entry.id, params)
    end
  end

  defp reserve_for_membership!(membership, request) do
    occurred_on = request_date(request)
    base_entitlement = entitlement_for_membership(membership)
    mode = entitlement_enforcement_mode()
    request = put_local_start(request)

    {subscription, request} =
      select_subscription(membership.id, base_entitlement, request, occurred_on)

    if is_nil(subscription) and mode != :observe and Map.get(request, :actor_role) != :admin and
         frozen_subscriptions(membership.id, occurred_on) != [],
       do: Repo.rollback(:finance_membership_frozen)

    entitlement =
      if subscription do
        Map.put(base_entitlement, :plan, subscription.params_snapshot || %{})
      else
        base_entitlement
      end

    allowance = Map.get(request, :allowance)

    {period_start, period_end, committed, extensions, limit} =
      allowance_state(subscription, allowance, occurred_on, membership.id)

    policy_request =
      request
      |> Map.put(:committed, committed)
      |> Map.put(:limit, effective_limit(limit, extensions))

    case EntitlementPolicy.authorize(entitlement, policy_request,
           mode: mode,
           actor_role: Map.get(request, :actor_role)
         ) do
      {:ok, decision} ->
        if allowance && subscription do
          entry =
            insert_usage_entry!(%{
              membership_id: membership.id,
              membership_package_subscription_id: subscription.id,
              allowance_key: to_string(allowance),
              event_type: "reserve",
              quantity_delta: Map.get(request, :quantity, 1),
              period_start: period_start,
              period_end: period_end,
              source_context: to_string(Map.get(request, :source_context, "application")),
              source_id: Map.get(request, :source_id),
              idempotency_key: Map.fetch!(request, :idempotency_key),
              metadata: Map.get(request, :metadata, %{})
            })

          activate_on_first_use!(subscription, occurred_on)
          Map.put(entry, :decision, decision)
        else
          %{id: nil, decision: decision, observed?: true}
        end

      :ok ->
        %{id: nil, decision: %{remaining: :not_metered}, observed?: true}

      {:error, reason} ->
        case entitlement_denial_details(reason, policy_request) do
          nil -> Repo.rollback(reason)
          details -> Repo.rollback({reason, details})
        end

      {:error, reason, details} ->
        Repo.rollback({reason, details})
    end
  end

  defp entitlement_denial_details(:finance_channel_not_included, request),
    do: %{channel: Map.get(request, :channel)}

  defp entitlement_denial_details(:finance_capability_not_included, request),
    do: %{capability: Map.get(request, :capability)}

  defp entitlement_denial_details(:finance_class_type_not_included, request),
    do: %{class_type_id: Map.get(request, :class_type_id)}

  defp entitlement_denial_details(:finance_allowance_not_included, request),
    do: %{allowance: Map.get(request, :allowance)}

  defp entitlement_denial_details(_reason, _request), do: nil

  defp authorize_missing_profile!(request) do
    case EntitlementPolicy.authorize(nil, request,
           mode: entitlement_enforcement_mode(),
           actor_role: Map.get(request, :actor_role)
         ) do
      :ok -> %{id: nil, observed?: true}
      {:ok, decision} -> %{id: nil, observed?: true, decision: decision}
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp transition_entitlement(reservation_id, params, event_type, delta) do
    params = atom_key_map(params)

    Repo.transaction(fn ->
      idempotency_key = Map.fetch!(params, :idempotency_key)

      case tenant_scope(FinanceEntitlementUsageEntry)
           |> where([entry], entry.idempotency_key == ^idempotency_key)
           |> Repo.one() do
        %FinanceEntitlementUsageEntry{} = existing ->
          normalize_usage_entry(existing)

        nil ->
          reservation =
            Repo.one(
              from entry in tenant_scope(FinanceEntitlementUsageEntry),
                where: entry.id == ^reservation_id,
                lock: "FOR UPDATE"
            ) || Repo.rollback(:not_found)

          if reservation.event_type != "reserve",
            do: Repo.rollback(:invalid_entitlement_reservation)

          terminal =
            tenant_scope(FinanceEntitlementUsageEntry)
            |> where([entry], entry.parent_entry_id == ^reservation.id)
            |> Repo.one()

          if terminal, do: Repo.rollback(:entitlement_reservation_already_closed)

          insert_usage_entry!(%{
            membership_id: reservation.membership_id,
            membership_package_subscription_id: reservation.membership_package_subscription_id,
            allowance_key: reservation.allowance_key,
            event_type: event_type,
            quantity_delta: if(delta == :reverse, do: -reservation.quantity_delta, else: delta),
            period_start: reservation.period_start,
            period_end: reservation.period_end,
            source_context: reservation.source_context,
            source_id: Map.get(params, :source_id, reservation.source_id),
            parent_entry_id: reservation.id,
            reason: Map.get(params, :reason),
            idempotency_key: idempotency_key,
            metadata: Map.get(params, :metadata, %{})
          })
      end
    end)
  end

  defp effective_entitlement(membership, occurred_on) do
    frozen = frozen_subscriptions(membership.id, occurred_on)

    # A frozen subscription stays visible (marked frozen) while it is paused.
    {subscription, base} =
      case effective_subscription(membership.id, occurred_on) do
        nil when frozen != [] ->
          {MembershipPackageSubscription
           |> Repo.get(hd(frozen).membership_package_subscription_id),
           membership
           |> entitlement_for_membership()
           |> Map.put(:frozen_until, hd(frozen).ends_on)}

        subscription ->
          {subscription, entitlement_for_membership(membership)}
      end

    others =
      if subscription,
        do:
          membership.id
          |> effective_subscriptions(occurred_on)
          |> Enum.reject(&(&1.id == subscription.id)),
        else: []

    case subscription && merged_plan([subscription | others]) do
      {:ok, plan, plans} ->
        # Each allowance is shown from the first subscription that holds it,
        # matching the order reservations try (ADR-098).
        allowances =
          plans
          |> Enum.flat_map(fn {sub, sub_plan} ->
            Enum.map(sub_plan.allowances, fn {allowance, config} -> {allowance, config, sub} end)
          end)
          |> Enum.uniq_by(&elem(&1, 0))
          |> Map.new(fn {allowance, config, sub} ->
            {period_start, period_end, committed, extensions, limit} =
              allowance_state(sub, allowance, occurred_on, membership.id)

            {allowance,
             %{
               limit: limit,
               period: config.period,
               period_start: period_start,
               period_end: period_end,
               committed: committed,
               extensions: extensions,
               remaining: remaining(limit, extensions, committed)
             }}
          end)

        entries =
          FinanceEntitlementUsageEntry
          |> where([entry], entry.membership_id == ^membership.id)
          |> order_by([entry], desc: entry.inserted_at)
          |> Repo.all()
          |> Enum.map(&normalize_usage_entry/1)

        stacked = Enum.map(others, &normalize_subscription/1)

        base
        |> Map.put(:plan, serialize_entitlement_plan(plan))
        |> Map.put(:subscription, normalize_subscription(subscription))
        |> Map.put(:stacked_subscriptions, stacked)
        |> Map.put(:freezes, list_freezes(membership.user_id))
        |> Map.put(:allowances, allowances)
        |> Map.put(:usage_entries, entries)
        |> Map.put(:enforcement_mode, entitlement_enforcement_mode())

      _ ->
        base
        |> Map.put(:plan, nil)
        |> Map.put(:allowances, %{})
        |> Map.put(:usage_entries, [])
        |> Map.put(:enforcement_mode, entitlement_enforcement_mode())
    end
  end

  defp allowance_state(nil, _allowance, occurred_on, _membership_id),
    do: {occurred_on, occurred_on, 0, 0, nil}

  # `membership_id` is the person using the allowance; per-person quotas of a
  # shared subscription only count that person's usage (ADR-098).
  defp allowance_state(subscription, allowance, occurred_on, membership_id) do
    with {:ok, plan} <- EntitlementPlan.parse(subscription.params_snapshot || %{}),
         %{limit: limit, period: period} <- Map.get(plan.allowances, allowance) do
      {period_start, period_end} = AllowancePeriod.bounds(period, occurred_on, subscription)
      usage_by = if PaymentModelPolicy.per_person_usage?(plan), do: membership_id

      entries =
        FinanceEntitlementUsageEntry
        |> where([entry], entry.membership_package_subscription_id == ^subscription.id)
        |> where([entry], entry.allowance_key == ^to_string(allowance))
        |> where([entry], entry.period_start == ^period_start and entry.period_end == ^period_end)
        |> usage_by_member(usage_by)
        |> Repo.all()

      committed =
        entries
        |> Enum.reject(&(&1.event_type == "adjustment"))
        |> Enum.reduce(0, &(&1.quantity_delta + &2))
        |> max(0)

      extensions =
        entries
        |> Enum.filter(&(&1.event_type == "adjustment"))
        |> Enum.reduce(0, &(&1.quantity_delta + &2))
        |> then(&max(-&1, 0))

      carried =
        rollover_units(subscription, allowance, period, limit, occurred_on, plan, usage_by)

      {period_start, period_end, committed, extensions + carried, limit}
    else
      _ -> {occurred_on, occurred_on, 0, 0, nil}
    end
  end

  # ADR-097: unused units of the previous calendar period, capped by rollover_max.
  defp usage_by_member(query, nil), do: query

  defp usage_by_member(query, membership_id),
    do: where(query, [entry], entry.membership_id == ^membership_id)

  defp rollover_units(subscription, allowance, period, limit, occurred_on, plan, usage_by) do
    rollover_max = plan.terms[:rollover_max] || 0

    with true <- rollover_max > 0 and is_integer(limit),
         {previous_start, previous_end} <- AllowancePeriod.previous_bounds(period, occurred_on),
         true <-
           is_nil(subscription.starts_on) or
             Date.compare(subscription.starts_on, previous_end) != :gt do
      previous =
        FinanceEntitlementUsageEntry
        |> where([entry], entry.membership_package_subscription_id == ^subscription.id)
        |> where([entry], entry.allowance_key == ^to_string(allowance))
        |> where(
          [entry],
          entry.period_start == ^previous_start and entry.period_end == ^previous_end
        )
        |> usage_by_member(usage_by)
        |> Repo.all()

      committed =
        previous
        |> Enum.reject(&(&1.event_type == "adjustment"))
        |> Enum.reduce(0, &(&1.quantity_delta + &2))
        |> max(0)

      extensions =
        previous
        |> Enum.filter(&(&1.event_type == "adjustment"))
        |> Enum.reduce(0, &(&1.quantity_delta + &2))
        |> then(&max(-&1, 0))

      SubscriptionTerms.carry_over(limit, extensions, committed, rollover_max)
    else
      _ -> 0
    end
  end

  defp effective_subscription(membership_id, occurred_on) do
    membership_id
    |> effective_subscriptions(occurred_on)
    |> List.first()
  end

  # ADR-096: stacked subscriptions in the order they should be consumed.
  # ADR-098: shared subscriptions the member benefits from are included, and
  # add-ons only while their base is usable.
  defp effective_subscriptions(membership_id, occurred_on) do
    shared_ids = beneficiary_subscription_ids(membership_id)

    subscriptions =
      MembershipPackageSubscription
      |> where(
        [subscription],
        subscription.membership_id == ^membership_id or subscription.id in ^shared_ids
      )
      |> where([subscription], subscription.status == "active")
      |> where(
        [subscription],
        is_nil(subscription.starts_on) or subscription.starts_on <= ^occurred_on
      )
      |> where(
        [subscription],
        is_nil(subscription.ends_on) or subscription.ends_on >= ^occurred_on
      )
      |> Repo.all()

    frozen = frozen_subscription_ids(Enum.map(subscriptions, & &1.id), occurred_on)

    subscriptions
    |> Enum.reject(&(&1.id in frozen))
    |> PaymentModelPolicy.drop_orphan_add_ons()
    |> SubscriptionSelection.order()
    |> with_lapsed_fallback(membership_id, occurred_on)
  end

  # ADR-112: during the grace slack after the last subscription ended, the one
  # that just lapsed keeps governing (its allowances apply until the slack is
  # over).
  defp with_lapsed_fallback([], membership_id, occurred_on) do
    case lapsed_subscription(membership_id, occurred_on, subscription_grace_days()) do
      nil -> []
      lapsed -> [lapsed]
    end
  end

  defp with_lapsed_fallback(subscriptions, _membership_id, _occurred_on), do: subscriptions

  defp beneficiary_subscription_ids(membership_id) do
    FinanceSubscriptionBeneficiary
    |> tenant_scope()
    |> where([beneficiary], beneficiary.membership_id == ^membership_id)
    |> where([beneficiary], is_nil(beneficiary.removed_at))
    |> select([beneficiary], beneficiary.membership_package_subscription_id)
    |> Repo.all()
  end

  defp frozen_subscription_ids([], _occurred_on), do: []

  defp frozen_subscription_ids(subscription_ids, occurred_on) do
    FinanceSubscriptionFreeze
    |> tenant_scope()
    |> where([freeze], freeze.membership_package_subscription_id in ^subscription_ids)
    |> where([freeze], is_nil(freeze.cancelled_at))
    |> where([freeze], freeze.starts_on <= ^occurred_on and freeze.ends_on >= ^occurred_on)
    |> select([freeze], freeze.membership_package_subscription_id)
    |> Repo.all()
  end

  # ADR-097: a subscription is unusable while one of its freezes covers the day.
  defp frozen_subscriptions(membership_id, occurred_on) do
    FinanceSubscriptionFreeze
    |> tenant_scope()
    |> where([freeze], freeze.membership_id == ^membership_id)
    |> where([freeze], is_nil(freeze.cancelled_at))
    |> where([freeze], freeze.starts_on <= ^occurred_on and freeze.ends_on >= ^occurred_on)
    |> Repo.all()
  end

  defp put_local_start(%{starts_at: %DateTime{} = starts_at} = request) do
    timezone = GymClock.zone() || "Etc/UTC"

    local =
      case DateTime.shift_zone(starts_at, timezone) do
        {:ok, local} -> local
        _ -> starts_at
      end

    request
    |> Map.put(:local_weekday, Date.day_of_week(DateTime.to_date(local)))
    |> Map.put(:local_time, DateTime.to_time(local))
  end

  defp put_local_start(request), do: request

  defp activate_on_first_use!(
         %MembershipPackageSubscription{activated_on: nil} = subscription,
         occurred_on
       ) do
    with {:ok, plan} <- EntitlementPlan.parse(subscription.params_snapshot || %{}),
         "first_use" <- plan.terms[:validity_starts],
         ends_on when not is_nil(ends_on) <-
           SubscriptionTerms.activation_ends_on(occurred_on, plan.terms[:validity]) do
      subscription
      |> MembershipPackageSubscription.changeset(%{activated_on: occurred_on, ends_on: ends_on})
      |> Repo.update()
      |> case do
        {:ok, _} -> :ok
        {:error, reason} -> Repo.rollback(reason)
      end
    else
      _ -> :ok
    end
  end

  defp activate_on_first_use!(_subscription, _occurred_on), do: :ok

  # Picks the first stacked subscription that authorizes the request under
  # enforcement and resolves class-type allowances against its plan. When none
  # authorizes, the primary subscription is used so the denial is reported
  # (or observed) against the membership's main contract.
  defp select_subscription(membership_id, entitlement, request, occurred_on) do
    candidates =
      Enum.map(effective_subscriptions(membership_id, occurred_on), fn subscription ->
        {subscription, resolve_request_allowance(subscription, request)}
      end)

    Enum.find(candidates, fn {subscription, candidate_request} ->
      allowance = Map.get(candidate_request, :allowance)

      {_start, _end, committed, extensions, limit} =
        allowance_state(subscription, allowance, occurred_on, membership_id)

      policy_request =
        candidate_request
        |> Map.put(:committed, committed)
        |> Map.put(:limit, effective_limit(limit, extensions))

      match?(
        {:ok, _},
        EntitlementPolicy.authorize(
          Map.put(entitlement, :plan, subscription.params_snapshot || %{}),
          policy_request,
          mode: :enforce_all,
          actor_role: Map.get(request, :actor_role)
        )
      )
    end)
    |> case do
      nil -> List.first(candidates) || {nil, request}
      selected -> selected
    end
  end

  defp resolve_request_allowance(subscription, request) do
    case EntitlementPlan.parse(subscription.params_snapshot || %{}) do
      {:ok, plan} ->
        Map.put(
          request,
          :allowance,
          EntitlementPlan.resolve_allowance(
            plan,
            Map.get(request, :allowance),
            Map.get(request, :class_type_id)
          )
        )

      _ ->
        request
    end
  end

  defp insert_usage_entry!(params) do
    case tenant_scope(FinanceEntitlementUsageEntry)
         |> where([entry], entry.idempotency_key == ^params.idempotency_key)
         |> Repo.one() do
      %FinanceEntitlementUsageEntry{} = entry ->
        normalize_usage_entry(entry)

      nil ->
        %FinanceEntitlementUsageEntry{}
        |> FinanceEntitlementUsageEntry.changeset(params)
        |> Repo.insert()
        |> case do
          {:ok, entry} -> normalize_usage_entry(entry)
          {:error, changeset} -> Repo.rollback(changeset)
        end
    end
  end

  defp lapsed_subscription(_membership_id, _occurred_on, grace_days) when grace_days <= 0,
    do: nil

  defp lapsed_subscription(membership_id, occurred_on, grace_days) do
    MembershipPackageSubscription
    |> where([subscription], subscription.membership_id == ^membership_id)
    |> where([subscription], subscription.status == "active")
    |> where([subscription], not is_nil(subscription.ends_on))
    |> where([subscription], subscription.ends_on < ^occurred_on)
    |> where([subscription], subscription.ends_on >= ^Date.add(occurred_on, -grace_days))
    |> order_by([subscription], desc: subscription.ends_on, desc: subscription.inserted_at)
    |> limit(1)
    |> Repo.one()
  end

  defp lapsed_subscription_ends_on(membership_id, today, grace_days) do
    case lapsed_subscription(membership_id, today, grace_days) do
      %MembershipPackageSubscription{ends_on: ends_on} -> ends_on
      nil -> nil
    end
  end

  defp subscription_grace_days do
    Map.get(get_finance_settings(), :subscription_grace_days, 0) || 0
  end

  defp normalize_usage_entry(entry) do
    %{
      id: entry.id,
      organization_id: entry.organization_id,
      membership_id: entry.membership_id,
      membership_package_subscription_id: entry.membership_package_subscription_id,
      allowance_key: entry.allowance_key,
      event_type: entry.event_type,
      quantity_delta: entry.quantity_delta,
      period_start: entry.period_start,
      period_end: entry.period_end,
      source_context: entry.source_context,
      source_id: entry.source_id,
      parent_entry_id: entry.parent_entry_id,
      admin_id: entry.admin_id,
      reason: entry.reason,
      idempotency_key: entry.idempotency_key,
      metadata: entry.metadata,
      inserted_at: entry.inserted_at
    }
  end

  defp package_identity_snapshot(package) do
    [package.code, package.name, package.family]
    |> Enum.find_value(fn
      value when is_binary(value) ->
        trimmed = String.trim(value)
        if trimmed == "", do: nil, else: trimmed

      _ ->
        nil
    end)
  end

  defp serialize_entitlement_plan(plan), do: EntitlementPlan.serialize(plan)

  # Compiled plans of the effective subscriptions, primary first, merged into
  # the plan the read model exposes. Unparseable snapshots are skipped.
  defp merged_plan(subscriptions) do
    plans =
      Enum.flat_map(subscriptions, fn subscription ->
        case EntitlementPlan.parse(subscription.params_snapshot || %{}) do
          {:ok, plan} -> [{subscription, plan}]
          _error -> []
        end
      end)

    case plans do
      [] -> nil
      plans -> {:ok, plans |> Enum.map(&elem(&1, 1)) |> EntitlementPlan.merge(), plans}
    end
  end

  defp remaining(:unlimited, _extensions, _committed), do: :unlimited
  defp remaining(limit, extensions, committed), do: max(limit + extensions - committed, 0)
  defp effective_limit(:unlimited, _extensions), do: :unlimited
  defp effective_limit(nil, _extensions), do: nil
  defp effective_limit(limit, extensions), do: limit + extensions

  defp entitlement_enforcement_mode do
    case get_finance_settings().entitlement_enforcement_mode do
      "enforce_managed" -> :enforce_managed
      "enforce_all" -> :enforce_all
      _ -> :observe
    end
  end

  defp atom_key_map(params) when is_map(params) do
    Map.new(params, fn
      {key, value} when is_atom(key) ->
        {key, value}

      {key, value} when is_binary(key) ->
        try do
          {String.to_existing_atom(key), value}
        rescue
          ArgumentError -> {key, value}
        end
    end)
  end

  @impl true
  def list_expiring_memberships(days), do: list_expiring_memberships(days, nil)

  defp list_expiring_memberships(days, users) do
    today = GymClock.today()
    cutoff = Date.add(GymClock.today(), parse_integer(days, 30))

    Membership
    |> for_users(users)
    |> where([membership], not is_nil(membership.expires_on))
    |> where([membership], membership.expires_on >= ^today)
    |> where([membership], membership.expires_on <= ^cutoff)
    |> where([membership], membership.status in ["active", "expiring", "trial"])
    |> order_by([membership], asc: membership.expires_on)
    |> Repo.all()
    |> Enum.map(&normalize_membership/1)
  end

  @impl true
  def operational_queues(params) do
    params = string_key_map(params)
    limit = parse_integer(params["limit"], 25)
    expiring_within_days = parse_integer(params["expires_within_days"], 30)
    # ADR-186 §7: a branch filter arrives as the users whose home branch it is.
    users = branch_users(params)

    %{
      expiring_memberships:
        Enum.take(list_expiring_memberships(expiring_within_days, users), limit),
      pending_payments: list_pending_payments(limit, users),
      overdue_invoices: list_overdue_invoices(limit, users),
      pending_referral_events: list_pending_referral_events(limit, users),
      pending_referral_rewards: list_pending_referral_rewards(limit, users),
      promotion_redemptions: list_recent_redemptions(limit, users)
    }
  end

  def financial_summary, do: financial_summary(%{})

  @impl true
  def financial_summary(params) do
    params = string_key_map(params || %{})
    since = summary_since(params["days"])
    users = branch_users(params)
    scope = %{users: users, location_ids: branch_location_ids(params)}
    renewal_metrics = renewal_invoice_metrics(users)
    first_month = GymClock.today() |> Date.beginning_of_month() |> Date.shift(month: -23)
    streams = revenue_by_stream(since, scope)

    {aggregate_status, aggregate_error, aggregate_rows} =
      case RepoContext.current_setting("app.organization_id") do
        # The aggregate view is per package, not per person, so a branch
        # filter reads the payments themselves (ADR-186 §7).
        _organization_id when is_list(users) ->
          {"available", nil, []}

        organization_id when is_binary(organization_id) ->
          case Repo.query(
                 """
                 SELECT period_start, user_type_snapshot, package_code, package_family,
                        membership_count, active_membership_count, expiring_membership_count,
                        paid_revenue_cents, pending_revenue_cents, promotion_redemption_count,
                        promotion_percent_redemption_count,
                        promotion_fixed_amount_redemption_count,
                        promotion_free_period_redemption_count,
                        promotion_manual_redemption_count,
                        promotion_realized_discount_cents,
                        referral_signup_count, pending_referral_reward_count,
                        credit_granted_cents, credit_applied_cents, credit_balance_cents
                 FROM finance_aggregates
                 WHERE organization_id = $1::uuid AND period_start >= $2
                 ORDER BY period_start DESC, package_code ASC
                 """,
                 [Ecto.UUID.dump!(organization_id), first_month]
               ) do
            {:ok, %{rows: rows}} ->
              {"available", nil, Enum.map(rows, &normalize_finance_aggregate_row/1)}

            {:error, reason} ->
              {"unavailable", inspect(reason), []}
          end

        _missing_scope ->
          {"unavailable", "missing_organization_scope", []}
      end

    %{
      aggregates: aggregate_rows,
      monthly_revenue:
        if(is_list(users),
          do: monthly_payment_revenue(scope, first_month),
          else: monthly_revenue(aggregate_rows, first_month)
        ),
      # ADR-192 §2: the same paid revenue split by stream, per month and in
      # the window. `monthly_revenue` and `totals` keep their meaning.
      monthly_revenue_by_stream: monthly_revenue_by_stream(first_month, scope),
      revenue_streams: streams.rows,
      aggregate_status: aggregate_status,
      aggregate_error: aggregate_error,
      period: %{since: since, days: parse_integer(params["days"], 30)},
      totals: %{
        active_memberships: active_membership_count(users),
        expiring_memberships: length(list_expiring_memberships(30, users)),
        paid_revenue_cents: total_paid_revenue_cents(since, scope),
        revenue_by_stream: streams.net_by_stream,
        credit_balance_cents: total_credit_balance_cents(users),
        outstanding_invoice_balance_cents: total_outstanding_invoice_balance_cents(users),
        overdue_invoice_balance_cents: total_overdue_invoice_balance_cents(users),
        invoice_credit_offset_cents: total_invoice_credit_offset_cents(users),
        renewal_invoices_issued_count: renewal_metrics.issued_count,
        renewal_invoices_paid_count: renewal_metrics.paid_count,
        renewal_conversion_percent: renewal_metrics.conversion_percent
      }
    }
  end

  @impl true
  def create_promotion_campaign(params) do
    %PromotionCampaign{}
    |> PromotionCampaign.changeset(params)
    |> Repo.insert()
    |> normalize_result(&normalize_promotion_campaign/1)
  end

  @impl true
  def list_promotion_campaigns do
    PromotionCampaign
    |> order_by([campaign], desc: campaign.inserted_at)
    |> Repo.all()
    |> Enum.map(&normalize_promotion_campaign/1)
  end

  @impl true
  def create_promotion_code(campaign_id, params) do
    case PromotionCampaign |> tenant_scope() |> Repo.get(campaign_id) do
      nil ->
        {:error, :not_found}

      %PromotionCampaign{} = campaign ->
        params =
          params
          |> string_key_map()
          |> Map.put("promotion_campaign_id", campaign.id)

        %PromotionCode{}
        |> PromotionCode.changeset(params)
        |> Repo.insert()
        |> normalize_result(&normalize_promotion_code/1)
    end
  end

  @impl true
  def list_promotion_codes(nil) do
    PromotionCode
    |> order_by([code], asc: code.code)
    |> Repo.all()
    |> Enum.map(&normalize_promotion_code/1)
  end

  def list_promotion_codes(campaign_id) do
    PromotionCode
    |> where([code], code.promotion_campaign_id == ^campaign_id)
    |> order_by([code], asc: code.code)
    |> Repo.all()
    |> Enum.map(&normalize_promotion_code/1)
  end

  @impl true
  def list_member_visible_promotions do
    campaigns =
      PromotionCampaign
      |> where([campaign], campaign.active == true)
      |> where([campaign], fragment("(?->>'member_visible') = 'true'", campaign.params))
      |> order_by([campaign], desc: campaign.inserted_at)
      |> Repo.all()
      |> Enum.map(&normalize_promotion_campaign/1)

    codes =
      case Enum.map(campaigns, & &1.id) do
        [] ->
          []

        ids ->
          PromotionCode
          |> where([code], code.promotion_campaign_id in ^ids and code.active == true)
          |> order_by([code], asc: code.code)
          |> Repo.all()
          |> Enum.map(&normalize_promotion_code/1)
      end

    {campaigns, codes}
  end

  @impl true
  def redeem_promotion(membership_id, params) do
    params = string_key_map(params)

    Repo.transaction(fn ->
      with %Membership{} = membership <- locked_membership(membership_id),
           :ok <- validate_redemption_links(membership.id, params),
           {:ok, redemption_params} <- build_redemption_params(membership, params) do
        %PromotionRedemption{}
        |> PromotionRedemption.changeset(redemption_params)
        |> Repo.insert()
        |> case do
          {:ok, redemption} -> normalize_promotion_redemption(redemption)
          {:error, reason} -> Repo.rollback(reason)
        end
      else
        nil -> Repo.rollback(:not_found)
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  @impl true
  def create_referral_program(params) do
    changeset = ReferralProgram.changeset(%ReferralProgram{}, params)

    # ADR-156: one active programme per box; activating one retires the other.
    Repo.transaction(fn ->
      retire_other_active_programs(changeset, nil)

      case Repo.insert(changeset) do
        {:ok, program} -> normalize_referral_program(program)
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  @impl true
  def update_referral_program(id, params) do
    case ReferralProgram |> tenant_scope() |> Repo.get(id) do
      nil ->
        {:error, :not_found}

      %ReferralProgram{} = program ->
        changeset = ReferralProgram.changeset(program, params)

        Repo.transaction(fn ->
          retire_other_active_programs(changeset, program.id)

          case Repo.update(changeset) do
            {:ok, program} -> normalize_referral_program(program)
            {:error, reason} -> Repo.rollback(reason)
          end
        end)
    end
  end

  @impl true
  def get_active_referral_program do
    ReferralProgram
    |> tenant_scope()
    |> where([program], program.active)
    |> Repo.one()
    |> case do
      nil -> nil
      program -> normalize_referral_program(program)
    end
  end

  @impl true
  def get_referral_program(id) do
    case ReferralProgram |> tenant_scope() |> Repo.get(id) do
      nil -> nil
      program -> normalize_referral_program(program)
    end
  end

  defp retire_other_active_programs(%Ecto.Changeset{valid?: true} = changeset, own_id) do
    if Ecto.Changeset.get_field(changeset, :active) do
      ReferralProgram
      |> tenant_scope()
      |> where([program], program.active)
      |> then(fn query ->
        if own_id, do: where(query, [program], program.id != ^own_id), else: query
      end)
      |> Repo.update_all(set: [active: false, updated_at: utc_now()])
    end

    :ok
  end

  defp retire_other_active_programs(_changeset, _own_id), do: :ok

  @impl true
  def list_referral_programs do
    ReferralProgram
    |> order_by([program], desc: program.active, asc: program.name)
    |> Repo.all()
    |> Enum.map(&normalize_referral_program/1)
  end

  @impl true
  def create_referral_event(params) do
    params = string_key_map(params)

    with {:ok, _program} <- active_referral_program(params["referral_program_id"]),
         {:ok, membership_user_id} <- referral_membership_user_id(params["membership_id"]),
         :ok <-
           ReferralPolicy.validate_event(%{
             referrer_user_id: params["referrer_user_id"],
             referred_user_id: params["referred_user_id"],
             membership_user_id: membership_user_id,
             referrer_role: params["referrer_role_snapshot"],
             referred_role: params["referred_role_snapshot"]
           }) do
      %ReferralEvent{}
      |> ReferralEvent.changeset(params)
      |> Repo.insert()
      |> normalize_result(&normalize_referral_event/1)
    end
  end

  @impl true
  def update_referral_status(id, status) do
    case ReferralEvent |> tenant_scope() |> Repo.get(id) do
      nil ->
        {:error, :not_found}

      %ReferralEvent{} = event ->
        with :ok <- ReferralLifecycle.validate_transition(event.status, status) do
          event
          |> ReferralEvent.changeset(%{status: status})
          |> Repo.update()
          |> normalize_result(&normalize_referral_event/1)
        end
    end
  end

  @impl true
  def list_referral_events do
    ReferralEvent
    |> tenant_scope()
    |> order_by([event], desc: event.inserted_at)
    |> Repo.all()
    |> Enum.map(&normalize_referral_event/1)
  end

  @impl true
  def create_referral_reward(referral_event_id, params) do
    case ReferralEvent |> tenant_scope() |> Repo.get(referral_event_id) do
      nil ->
        {:error, :not_found}

      %ReferralEvent{} = event ->
        with :ok <-
               ReferralPolicy.validate_reward_creation(
                 event.status,
                 referral_reward_exists?(event.id)
               ),
             {:ok, program} <- event_referral_program(event.referral_program_id) do
          params =
            params
            |> string_key_map()
            |> Map.put("referral_event_id", event.id)
            |> Map.put("recipient_user_id", event.referrer_user_id)
            |> Map.put("membership_id", event.membership_id)
            |> Map.put_new("reward_type", program.reward_type)
            |> Map.put_new("reward_value", program.reward_value)

          %ReferralReward{}
          |> ReferralReward.changeset(params)
          |> Repo.insert()
          |> normalize_result(&normalize_referral_reward/1)
        end
    end
  end

  @impl true
  def open_attributed_referral(params) do
    params = string_key_map(params)

    Repo.transaction(fn ->
      with %ReferralProgram{} = program <-
             ReferralProgram |> tenant_scope() |> Repo.get(params["referral_program_id"]),
           %Membership{} = membership <- locked_membership(params["membership_id"]),
           :ok <-
             ReferralPolicy.validate_event(%{
               referrer_user_id: params["referrer_user_id"],
               referred_user_id: params["referred_user_id"],
               membership_user_id: membership.user_id,
               referrer_role: params["referrer_role_snapshot"],
               referred_role: params["referred_role_snapshot"]
             }),
           {:ok, event} <-
             %ReferralEvent{}
             |> ReferralEvent.changeset(
               Map.merge(params, %{
                 "referral_program_id" => program.id,
                 "status" => "pending",
                 "signup_source_snapshot" => "referral"
               })
             )
             |> Repo.insert(),
           {:ok, _membership} <- stamp_referred_membership(membership, event.referrer_user_id) do
        normalize_referral_event(event)
      else
        nil -> Repo.rollback(:not_found)
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  # The friend's Finance record says who brought them, once.
  defp stamp_referred_membership(%Membership{referred_by_user_id: nil} = membership, referrer_id) do
    membership
    |> Membership.changeset(%{referred_by_user_id: referrer_id, signup_source: "referral"})
    |> Repo.update()
  end

  defp stamp_referred_membership(membership, _referrer_id), do: {:ok, membership}

  @impl true
  def count_referral_events_since(referrer_user_id, since) do
    ReferralEvent
    |> tenant_scope()
    |> where([event], event.referrer_user_id == ^referrer_user_id)
    |> where([event], event.status != "rejected" and event.inserted_at >= ^since)
    |> Repo.aggregate(:count)
  end

  @impl true
  def referral_outcomes([]), do: %{}

  def referral_outcomes(event_ids) do
    rewards =
      ReferralReward
      |> tenant_scope()
      |> where([reward], reward.referral_event_id in ^event_ids)
      |> Repo.all()
      |> Map.new(&{&1.referral_event_id, normalize_referral_reward(&1)})

    ReferralEvent
    |> tenant_scope()
    |> where([event], event.id in ^event_ids)
    |> Repo.all()
    |> Map.new(fn event ->
      {event.id,
       %{
         event: normalize_referral_event(event),
         reward: Map.get(rewards, event.id)
       }}
    end)
  end

  @impl true
  def extend_current_subscription(membership_id, days)
      when is_integer(days) and days > 0 and days <= 365 do
    Repo.transaction(fn ->
      with %Membership{} = membership <- locked_membership(membership_id),
           %MembershipPackageSubscription{} = subscription <-
             current_subscription(membership.id),
           {:ok, extended} <-
             subscription
             |> MembershipPackageSubscription.changeset(%{
               "ends_on" => Date.add(subscription.ends_on, days)
             })
             |> Repo.update() do
        refresh_entitlement_snapshot(membership.id)
        %{subscription_id: extended.id, ends_on: extended.ends_on}
      else
        nil -> Repo.rollback(:no_active_subscription)
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  def extend_current_subscription(_membership_id, _days), do: {:error, :invalid_days}

  # ADR-254: undoing an import cancels the subscription it assigned.
  @impl true
  def cancel_subscription(membership_id, subscription_id) do
    Repo.transaction(fn ->
      with %Membership{} = membership <- locked_membership(membership_id),
           %MembershipPackageSubscription{} = subscription <-
             MembershipPackageSubscription
             |> tenant_scope()
             |> where([s], s.id == ^subscription_id and s.membership_id == ^membership.id)
             |> lock("FOR UPDATE")
             |> Repo.one(),
           {:ok, cancelled} <-
             subscription
             |> MembershipPackageSubscription.changeset(%{"status" => "cancelled"})
             |> Repo.update() do
        refresh_entitlement_snapshot(membership.id)
        normalize_subscription(cancelled)
      else
        nil -> Repo.rollback(:not_found)
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp current_subscription(membership_id) do
    MembershipPackageSubscription
    |> tenant_scope()
    |> where([s], s.membership_id == ^membership_id and s.status == "active")
    |> where([s], not is_nil(s.ends_on))
    |> order_by([s], desc: s.ends_on)
    |> limit(1)
    |> lock("FOR UPDATE")
    |> Repo.one()
  end

  @impl true
  def list_referral_rewards do
    ReferralReward
    |> tenant_scope()
    |> order_by([reward], desc: reward.inserted_at)
    |> Repo.all()
    |> Enum.map(&normalize_referral_reward/1)
  end

  @impl true
  def update_referral_reward_status(id, status) do
    case ReferralReward |> tenant_scope() |> Repo.get(id) do
      nil ->
        {:error, :not_found}

      %ReferralReward{} = reward ->
        with :ok <- validate_reward_transition(reward.status, status),
             {:ok, event} <- get_reward_event(reward),
             :ok <- validate_reward_event_status(event, status),
             {:ok, updated_reward} <- update_reward_and_event(reward, event, status) do
          {:ok, normalize_referral_reward(updated_reward)}
        end
    end
  end

  defp validate_reward_transition(current_status, next_status) do
    ReferralLifecycle.validate_reward_transition(current_status, next_status)
  end

  defp update_reward_and_event(reward, event, status) do
    Repo.transaction(fn ->
      params =
        %{status: status}
        |> maybe_put_applied_at(status, reward.applied_at)

      updated_reward =
        reward
        |> ReferralReward.changeset(params)
        |> Repo.update()
        |> case do
          {:ok, updated_reward} -> updated_reward
          {:error, reason} -> Repo.rollback(reason)
        end

      updated_reward =
        if status == "applied" and event.status != "applied" do
          event
          |> ReferralEvent.changeset(%{status: "applied"})
          |> Repo.update()
          |> case do
            {:ok, _event} -> updated_reward
            {:error, reason} -> Repo.rollback(reason)
          end
        else
          updated_reward
        end

      fulfill_referral_reward(updated_reward, status)
    end)
  end

  defp fulfill_referral_reward(%ReferralReward{} = reward, "applied") do
    case ReferralRewardFulfillment.plan(reward) do
      {:ok, {:credit_grant, amount_cents}} ->
        sync_referral_reward_credit(reward, amount_cents, amount_cents)

      {:ok, plan} when plan in [:lifecycle_only, :renewal_discount] ->
        reward

      {:error, reason} ->
        Repo.rollback(reason)
    end
  end

  defp fulfill_referral_reward(%ReferralReward{} = reward, "rejected") do
    case ReferralRewardFulfillment.plan(reward) do
      {:ok, {:credit_grant, amount_cents}} ->
        sync_referral_reward_credit(reward, amount_cents, 0)

      {:ok, plan} when plan in [:lifecycle_only, :renewal_discount] ->
        reward

      {:error, reason} ->
        Repo.rollback(reason)
    end
  end

  defp fulfill_referral_reward(%ReferralReward{} = reward, _status), do: reward

  defp sync_referral_reward_credit(%ReferralReward{} = reward, amount_cents, target_cents) do
    current_cents = referral_reward_credit_total(reward.id)
    delta_cents = target_cents - current_cents

    if delta_cents == 0 do
      reward
    else
      with %Membership{} = membership <-
             Membership
             |> tenant_scope()
             |> Repo.get_by(user_id: reward.recipient_user_id),
           {:ok, _entry} <-
             create_referral_reward_credit_adjustment(
               reward,
               membership,
               amount_cents,
               target_cents,
               delta_cents
             ) do
        reward
      else
        nil -> Repo.rollback(:recipient_membership_not_found)
        {:error, reason} -> Repo.rollback(reason)
      end
    end
  end

  defp create_referral_reward_credit_adjustment(
         reward,
         membership,
         amount_cents,
         target_cents,
         delta_cents
       ) do
    create_credit_entry(%{
      "membership_id" => membership.id,
      "user_id" => membership.user_id,
      "referral_reward_id" => reward.id,
      "source_type" => referral_reward_credit_source(delta_cents),
      "entry_type" => referral_reward_credit_entry_type(delta_cents),
      "amount_cents" => delta_cents,
      "currency" => "EUR",
      "occurred_on" => GymClock.today(),
      "occurred_at" => referral_reward_credit_occurred_at(reward, delta_cents),
      "description" => referral_reward_credit_description(delta_cents),
      "reversed_credit_ledger_entry_id" =>
        referral_reward_credit_reversed_entry_id(reward.id, delta_cents),
      "idempotency_key" => referral_reward_credit_idempotency_key(reward.id),
      "params" => %{
        referral_event_id: reward.referral_event_id,
        reward_type: reward.reward_type,
        reward_value: amount_cents,
        target_cents: target_cents
      }
    })
  end

  defp referral_reward_credit_total(reward_id) do
    FinanceCreditLedgerEntry
    |> where([entry], entry.referral_reward_id == ^reward_id)
    |> where([entry], is_nil(entry.deleted_at))
    |> Repo.aggregate(:sum, :amount_cents)
    |> case do
      nil -> 0
      value -> value
    end
  end

  defp referral_reward_credit_source(delta_cents) when delta_cents > 0, do: "referral_reward"
  defp referral_reward_credit_source(_delta_cents), do: "reversal"

  defp referral_reward_credit_entry_type(delta_cents) when delta_cents > 0, do: "grant"
  defp referral_reward_credit_entry_type(_delta_cents), do: "reversal"

  defp referral_reward_credit_occurred_at(reward, delta_cents) when delta_cents > 0,
    do: reward.applied_at || utc_now()

  defp referral_reward_credit_occurred_at(_reward, _delta_cents), do: utc_now()

  defp referral_reward_credit_description(delta_cents) when delta_cents > 0,
    do: "Referral reward credit"

  defp referral_reward_credit_description(_delta_cents), do: "Referral reward credit reversal"

  defp referral_reward_credit_reversed_entry_id(_reward_id, delta_cents) when delta_cents > 0,
    do: nil

  defp referral_reward_credit_reversed_entry_id(reward_id, _delta_cents) do
    FinanceCreditLedgerEntry
    |> where([entry], entry.referral_reward_id == ^reward_id)
    |> where([entry], entry.amount_cents > 0)
    |> where([entry], is_nil(entry.deleted_at))
    |> order_by([entry], desc: entry.occurred_at, desc: entry.inserted_at)
    |> limit(1)
    |> Repo.one()
    |> case do
      nil -> nil
      entry -> entry.id
    end
  end

  defp referral_reward_credit_idempotency_key(reward_id) do
    adjustment_count =
      FinanceCreditLedgerEntry
      |> where([entry], entry.referral_reward_id == ^reward_id)
      |> Repo.aggregate(:count, :id)

    "referral_reward:#{reward_id}:adjustment:#{adjustment_count + 1}"
  end

  defp locked_membership(membership_id) do
    Membership
    |> tenant_scope()
    |> where([membership], membership.id == ^membership_id)
    |> lock("FOR UPDATE")
    |> Repo.one()
  end

  defp locked_payment(payment_id) do
    MembershipPayment
    |> tenant_scope()
    |> where([payment], payment.id == ^payment_id)
    |> where([payment], is_nil(payment.deleted_at))
    |> lock("FOR UPDATE")
    |> Repo.one()
  end

  defp locked_credit_ledger_entry(entry_id) do
    FinanceCreditLedgerEntry
    |> tenant_scope()
    |> where([entry], entry.id == ^entry_id)
    |> where([entry], is_nil(entry.deleted_at))
    |> lock("FOR UPDATE")
    |> Repo.one()
  end

  defp locked_invoice(invoice_id) do
    FinanceInvoice
    |> tenant_scope()
    |> where([invoice], invoice.id == ^invoice_id)
    |> where([invoice], is_nil(invoice.deleted_at))
    |> lock("FOR UPDATE")
    |> Repo.one()
  end

  defp locked_invoice_for_purge(invoice_id) do
    FinanceInvoice
    |> tenant_scope()
    |> where([invoice], invoice.id == ^invoice_id)
    |> lock("FOR UPDATE")
    |> Repo.one()
  end

  defp locked_payment_for_purge(payment_id) do
    MembershipPayment
    |> tenant_scope()
    |> where([payment], payment.id == ^payment_id)
    |> lock("FOR UPDATE")
    |> Repo.one()
  end

  defp normalize_cleanup_record_type(value) when value in [:invoice, :receipt], do: :invoice
  defp normalize_cleanup_record_type(value) when value in [:payment, :transaction], do: :payment

  defp normalize_cleanup_record_type(value) when is_binary(value) do
    case String.downcase(value) do
      value when value in ["invoice", "receipt"] -> :invoice
      value when value in ["payment", "transaction"] -> :payment
      _ -> :unknown
    end
  end

  defp normalize_cleanup_record_type(_value), do: :unknown

  defp soft_delete_invoice_record(invoice_id, admin_id, params) do
    Repo.transaction(fn ->
      case locked_invoice_for_purge(invoice_id) do
        nil ->
          Repo.rollback(:not_found)

        %FinanceInvoice{deleted_at: deleted_at} when not is_nil(deleted_at) ->
          Repo.rollback(:not_found)

        %FinanceInvoice{} = invoice ->
          deletion_params = deletion_params(admin_id, params)

          deleted_invoice =
            invoice
            |> FinanceInvoice.changeset(deletion_params)
            |> Repo.update()
            |> case do
              {:ok, updated} -> updated
              {:error, reason} -> Repo.rollback(reason)
            end

          soft_delete_invoice_payments!(invoice.id, deletion_params)
          soft_delete_invoice_reversals!(invoice.id, deletion_params)
          soft_delete_invoice_credit_entries!(invoice.id, deletion_params)
          refresh_entitlement_snapshot(invoice.membership_id)

          %{
            record: cleanup_invoice_record(deleted_invoice),
            purged_linked_records: linked_finance_record_counts(invoice.id)
          }
      end
    end)
  end

  defp soft_delete_payment_record(payment_id, admin_id, params) do
    Repo.transaction(fn ->
      case locked_payment_for_purge(payment_id) do
        nil ->
          Repo.rollback(:not_found)

        %MembershipPayment{deleted_at: deleted_at} when not is_nil(deleted_at) ->
          Repo.rollback(:not_found)

        %MembershipPayment{} = payment ->
          deletion_params = deletion_params(admin_id, params)

          deleted_payment =
            payment
            |> MembershipPayment.changeset(deletion_params)
            |> Repo.update()
            |> case do
              {:ok, updated} -> updated
              {:error, reason} -> Repo.rollback(reason)
            end

          soft_delete_payment_reversals!(payment.id, deletion_params)
          soft_delete_payment_credit_entries!(payment.id, deletion_params)
          refresh_invoice_and_entitlement(payment.finance_invoice_id, payment.membership_id)

          %{record: cleanup_payment_record(deleted_payment)}
      end
    end)
  end

  defp deletion_params(admin_id, params) do
    %{
      "deleted_at" => utc_now(),
      "deleted_by_id" => admin_id,
      "deletion_reason" => params["reason"] || params["deletion_reason"] || "Admin purge"
    }
  end

  defp soft_delete_invoice_payments!(invoice_id, deletion_params) do
    MembershipPayment
    |> where([payment], payment.finance_invoice_id == ^invoice_id)
    |> where([payment], is_nil(payment.deleted_at))
    |> Repo.all()
    |> Enum.each(fn payment ->
      payment
      |> MembershipPayment.changeset(deletion_params)
      |> Repo.update!()
    end)
  end

  defp soft_delete_invoice_reversals!(invoice_id, deletion_params) do
    FinancePaymentReversal
    |> where([reversal], reversal.finance_invoice_id == ^invoice_id)
    |> where([reversal], is_nil(reversal.deleted_at))
    |> Repo.all()
    |> Enum.each(fn reversal ->
      reversal
      |> FinancePaymentReversal.changeset(deletion_params)
      |> Repo.update!()
    end)
  end

  defp soft_delete_invoice_credit_entries!(invoice_id, deletion_params) do
    FinanceCreditLedgerEntry
    |> where([entry], entry.finance_invoice_id == ^invoice_id)
    |> where([entry], is_nil(entry.deleted_at))
    |> Repo.all()
    |> Enum.each(fn entry ->
      entry
      |> FinanceCreditLedgerEntry.changeset(deletion_params)
      |> Repo.update!()
    end)
  end

  defp soft_delete_payment_reversals!(payment_id, deletion_params) do
    FinancePaymentReversal
    |> where([reversal], reversal.membership_payment_id == ^payment_id)
    |> where([reversal], is_nil(reversal.deleted_at))
    |> Repo.all()
    |> Enum.each(fn reversal ->
      reversal
      |> FinancePaymentReversal.changeset(deletion_params)
      |> Repo.update!()
    end)
  end

  defp soft_delete_payment_credit_entries!(payment_id, deletion_params) do
    FinanceCreditLedgerEntry
    |> where([entry], entry.membership_payment_id == ^payment_id)
    |> where([entry], is_nil(entry.deleted_at))
    |> Repo.all()
    |> Enum.each(fn entry ->
      entry
      |> FinanceCreditLedgerEntry.changeset(deletion_params)
      |> Repo.update!()
    end)
  end

  defp linked_finance_record_counts(invoice_id) do
    %{
      payments:
        MembershipPayment
        |> where([payment], payment.finance_invoice_id == ^invoice_id)
        |> where([payment], not is_nil(payment.deleted_at))
        |> Repo.aggregate(:count),
      reversals:
        FinancePaymentReversal
        |> where([reversal], reversal.finance_invoice_id == ^invoice_id)
        |> where([reversal], not is_nil(reversal.deleted_at))
        |> Repo.aggregate(:count),
      credit_ledger_entries:
        FinanceCreditLedgerEntry
        |> where([entry], entry.finance_invoice_id == ^invoice_id)
        |> where([entry], not is_nil(entry.deleted_at))
        |> Repo.aggregate(:count)
    }
  end

  defp scoped_idempotency_key(action, membership_id, params) do
    "finance_credit:#{action}:#{membership_id}:#{params["request_id"]}"
  end

  defp scoped_finance_key(action, membership_id, params) do
    "finance:#{action}:#{membership_id}:#{params["request_id"]}"
  end

  defp require_request_id(%{"request_id" => request_id}) when is_binary(request_id) do
    case Ecto.UUID.cast(request_id) do
      {:ok, _uuid} -> :ok
      :error -> {:error, :request_id_required}
    end
  end

  defp require_request_id(_params), do: {:error, :request_id_required}

  defp manual_credit_params(params) do
    params
    |> Map.take(["request_id"])
    |> Map.put("origin", "admin_manual_credit")
  end

  defp credit_application_params(params) do
    params
    |> Map.take(["request_id"])
    |> Map.put("origin", "admin_credit_application")
  end

  defp reversal_params(params, original_id) do
    params
    |> Map.take(["request_id"])
    |> Map.put("origin", "admin_reversal")
    |> Map.put("original_id", original_id)
  end

  defp payment_reversal_type(%MembershipPayment{payment_status: "waived"}), do: "waiver_reversal"
  defp payment_reversal_type(%MembershipPayment{}), do: "refund"

  defp default_invoice_due_date(%FinanceInvoice{} = invoice) do
    if receipt_invoice?(invoice), do: nil, else: GymClock.today()
  end

  defp receipt_invoice?(%FinanceInvoice{} = invoice),
    do: (invoice.params || %{})["document_kind"] == "receipt"

  defp create_payment_reversal(params) do
    case existing_payment_reversal(params["idempotency_key"] || params[:idempotency_key]) do
      %FinancePaymentReversal{} = reversal ->
        {:ok, normalize_payment_reversal(reversal)}

      nil ->
        %FinancePaymentReversal{}
        |> FinancePaymentReversal.changeset(params)
        |> Repo.insert()
        |> case do
          {:ok, reversal} ->
            {:ok, normalize_payment_reversal(reversal)}

          {:error, %Ecto.Changeset{} = changeset} ->
            case existing_payment_reversal(params["idempotency_key"] || params[:idempotency_key]) do
              %FinancePaymentReversal{} = reversal -> {:ok, normalize_payment_reversal(reversal)}
              nil -> {:error, changeset}
            end
        end
    end
  end

  defp existing_payment_reversal(nil), do: nil
  defp existing_payment_reversal(""), do: nil

  defp existing_payment_reversal(idempotency_key) when is_binary(idempotency_key),
    do: Repo.get_by(FinancePaymentReversal, idempotency_key: idempotency_key)

  defp create_credit_entry(params) do
    case existing_credit_entry(params["idempotency_key"] || params[:idempotency_key]) do
      %FinanceCreditLedgerEntry{} = entry ->
        {:ok, normalize_credit_ledger_entry(entry)}

      nil ->
        %FinanceCreditLedgerEntry{}
        |> FinanceCreditLedgerEntry.changeset(params)
        |> Repo.insert()
        |> case do
          {:ok, entry} ->
            {:ok, normalize_credit_ledger_entry(entry)}

          {:error, %Ecto.Changeset{} = changeset} ->
            case existing_credit_entry(params["idempotency_key"] || params[:idempotency_key]) do
              %FinanceCreditLedgerEntry{} = entry -> {:ok, normalize_credit_ledger_entry(entry)}
              nil -> {:error, changeset}
            end
        end
    end
  end

  defp existing_credit_entry(nil), do: nil
  defp existing_credit_entry(""), do: nil

  defp existing_credit_entry(idempotency_key) when is_binary(idempotency_key),
    do: Repo.get_by(FinanceCreditLedgerEntry, idempotency_key: idempotency_key)

  defp list_credit_ledger_entries(membership_id) do
    FinanceCreditLedgerEntry
    |> where([entry], entry.membership_id == ^membership_id)
    |> where([entry], is_nil(entry.deleted_at))
    |> order_by([entry], desc: entry.occurred_at, desc: entry.inserted_at)
    |> Repo.all()
    |> Enum.map(&normalize_credit_ledger_entry/1)
  end

  defp list_payment_reversals(membership_id) do
    FinancePaymentReversal
    |> where([reversal], reversal.membership_id == ^membership_id)
    |> where([reversal], is_nil(reversal.deleted_at))
    |> order_by([reversal], desc: reversal.occurred_at, desc: reversal.inserted_at)
    |> Repo.all()
    |> Enum.map(&normalize_payment_reversal/1)
  end

  defp list_invoices(membership_id) do
    FinanceInvoice
    |> where([invoice], invoice.membership_id == ^membership_id)
    |> where([invoice], is_nil(invoice.deleted_at))
    |> order_by([invoice], desc: invoice.inserted_at)
    |> Repo.all()
    |> Enum.map(&normalize_invoice_with_balance/1)
  end

  defp maybe_prefill_invoice_from_subscription(_membership_id, %{"lines" => lines} = params)
       when is_list(lines) and length(lines) > 0 do
    {:ok, params}
  end

  defp maybe_prefill_invoice_from_subscription(
         membership_id,
         %{"membership_package_subscription_id" => subscription_id} = params
       )
       when is_binary(subscription_id) and subscription_id != "" do
    case MembershipPackageSubscription |> tenant_scope() |> Repo.get(subscription_id) do
      nil ->
        {:error, :not_found}

      %MembershipPackageSubscription{} = subscription ->
        with :ok <-
               MembershipLinks.validate_optional_link(
                 :membership_package_subscription_id,
                 membership_id,
                 subscription.membership_id
               ) do
          amount_cents =
            parse_integer(params["amount_cents"], subscription.price_cents_snapshot || 0)

          description =
            params["description"] || params["notes"] ||
              "Package: #{subscription.package_code_snapshot}"

          {:ok,
           params
           |> Map.put("amount_cents", amount_cents)
           |> Map.put_new("line_type", "membership_package")
           |> Map.put_new("description", description)
           |> Map.put_new("notes", description)
           |> Map.put(
             "lines",
             [
               %{
                 "membership_package_subscription_id" => subscription.id,
                 "line_type" => "membership_package",
                 "description" => description,
                 "quantity" => 1,
                 "unit_amount_cents" => amount_cents,
                 "discount_cents" => parse_integer(params["discount_cents"], 0),
                 "package_code_snapshot" => subscription.package_code_snapshot,
                 "package_family_snapshot" => subscription.package_family_snapshot
               }
             ] ++ joining_fee_lines(subscription)
           )}
        end
    end
  end

  defp maybe_prefill_invoice_from_subscription(_membership_id, params), do: {:ok, params}

  # ADR-097: the joining fee is charged once, on the first invoice of a
  # member's first subscription to the package.
  # ADR-098: the company pays for corporate seats, never the member.
  defp not_corporate_seat(%{corporate_client_id: nil}), do: :ok
  defp not_corporate_seat(_subscription), do: {:error, :corporate_seat_billed_to_company}

  # ADR-098: an add-on ends with its base, so it is not renewed without one.
  defp add_on_base_active(%{base_subscription_id: nil}), do: :ok

  defp add_on_base_active(%{base_subscription_id: base_id}) do
    base = MembershipPackageSubscription |> tenant_scope() |> Repo.get(base_id)

    if base &&
         InvoiceLifecycle.subscription_active?(
           base.status,
           base.starts_on,
           base.ends_on,
           GymClock.today()
         ),
       do: :ok,
       else: {:error, :add_on_base_ended}
  end

  defp joining_fee_lines(%{corporate_client_id: client_id}) when not is_nil(client_id), do: []

  defp joining_fee_lines(subscription) do
    fee = package_terms(subscription.params_snapshot)[:joining_fee_cents] || 0

    first_invoice? =
      not (FinanceInvoiceLine
           |> where([line], line.membership_package_subscription_id == ^subscription.id)
           |> Repo.exists?())

    first_subscription? =
      not (MembershipPackageSubscription
           |> where([other], other.membership_id == ^subscription.membership_id)
           |> where([other], other.membership_package_id == ^subscription.membership_package_id)
           |> where([other], other.id != ^subscription.id)
           |> where([other], other.inserted_at < ^subscription.inserted_at)
           |> Repo.exists?())

    if fee > 0 and first_invoice? and first_subscription? do
      [
        %{
          "membership_package_subscription_id" => subscription.id,
          "line_type" => "manual_charge",
          "charge_category" => "other",
          "description" => "Joining fee",
          "quantity" => 1,
          "unit_amount_cents" => fee,
          "discount_cents" => 0
        }
      ]
    else
      []
    end
  end

  # ADR-097: member discount for manual charges in the member's discount scope.
  defp apply_member_discount(membership, %{"lines" => lines} = params) when is_list(lines) do
    case effective_subscription(membership.id, GymClock.today()) do
      nil ->
        params

      subscription ->
        terms = package_terms(subscription.params_snapshot)

        Map.put(
          params,
          "lines",
          SubscriptionTerms.apply_member_discount(
            Enum.map(lines, &string_key_map/1),
            terms[:member_discount_percent] || 0,
            terms[:member_discount_scope] || []
          )
        )
    end
  end

  defp apply_member_discount(_membership, params), do: params

  defp invoice_line_params(%{"lines" => lines}) when is_list(lines) and length(lines) > 0 do
    normalize_line_params(lines)
  end

  defp invoice_line_params(params) do
    amount_cents = parse_integer(params["amount_cents"], 0)

    if amount_cents > 0 do
      normalize_line_params([
        %{
          "line_type" => params["line_type"] || "manual_charge",
          "description" => params["description"] || params["notes"] || "Manual invoice charge",
          "quantity" => 1,
          "unit_amount_cents" => amount_cents,
          "discount_cents" => parse_integer(params["discount_cents"], 0),
          "membership_package_subscription_id" => params["membership_package_subscription_id"]
        }
      ])
    else
      {:error, :invalid_invoice_amount}
    end
  end

  defp normalize_line_params(lines) do
    Enum.reduce_while(lines, {:ok, []}, fn line, {:ok, acc} ->
      case normalize_line_param(line) do
        {:ok, normalized_line} -> {:cont, {:ok, [normalized_line | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, normalized_lines} -> {:ok, Enum.reverse(normalized_lines)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp normalize_line_param(line) do
    line = string_key_map(line)

    with {:ok, quantity} <- parse_positive_integer(line["quantity"], 1),
         {:ok, unit_amount_cents} <- parse_non_negative_integer(line["unit_amount_cents"], 0),
         {:ok, discount_cents} <- parse_non_negative_integer(line["discount_cents"], 0),
         {:ok, total_cents} <-
           InvoiceLifecycle.line_total(quantity, unit_amount_cents, discount_cents) do
      {:ok,
       line
       |> Map.put_new("line_type", "manual_charge")
       |> Map.put("quantity", quantity)
       |> Map.put("unit_amount_cents", unit_amount_cents)
       |> Map.put("discount_cents", discount_cents)
       |> Map.put("total_cents", total_cents)
       |> Map.put_new("description", "Invoice line")}
    else
      {:error, :invalid_integer} -> {:error, :invalid_invoice_line_amount}
      {:error, reason} -> {:error, reason}
    end
  end

  defp renewal_subscription(membership_id, nil) do
    today = GymClock.today()

    MembershipPackageSubscription
    |> where([subscription], subscription.membership_id == ^membership_id)
    |> where([subscription], subscription.status == "active")
    |> where([subscription], is_nil(subscription.starts_on) or subscription.starts_on <= ^today)
    |> where([subscription], is_nil(subscription.ends_on) or subscription.ends_on >= ^today)
    |> order_by([subscription], desc: subscription.starts_on, desc: subscription.inserted_at)
    |> limit(1)
    |> Repo.one()
  end

  defp renewal_subscription(membership_id, ""), do: renewal_subscription(membership_id, nil)

  defp renewal_subscription(membership_id, subscription_id) do
    case MembershipPackageSubscription |> tenant_scope() |> Repo.get(subscription_id) do
      nil ->
        nil

      %MembershipPackageSubscription{} = subscription ->
        with :ok <-
               MembershipLinks.validate_optional_link(
                 :membership_package_subscription_id,
                 membership_id,
                 subscription.membership_id
               ),
             true <-
               InvoiceLifecycle.subscription_active?(
                 subscription.status,
                 subscription.starts_on,
                 subscription.ends_on,
                 GymClock.today()
               ) do
          subscription
        else
          false -> nil
          {:error, reason} -> {:error, reason}
        end
    end
  end

  defp renewal_invoice_exists?(membership_id, subscription_id, period_start, period_end) do
    Repo.exists?(
      from(invoice in FinanceInvoice,
        where: invoice.membership_id == ^membership_id,
        where: invoice.membership_package_subscription_id == ^subscription_id,
        where: invoice.invoice_type == "renewal",
        where: invoice.service_period_start == ^period_start,
        where: invoice.service_period_end == ^period_end,
        where: invoice.status != "void",
        where: is_nil(invoice.deleted_at)
      )
    )
  end

  defp invoice_paid_cents(invoice_id) do
    paid_cents =
      MembershipPayment
      |> where([payment], payment.finance_invoice_id == ^invoice_id)
      |> where([payment], payment.payment_status in ["paid", "waived"])
      |> where([payment], is_nil(payment.deleted_at))
      |> Repo.aggregate(:sum, :amount_cents)
      |> case do
        nil -> 0
        value -> value
      end

    max(paid_cents - invoice_payment_reversed_cents(invoice_id), 0)
  end

  defp invoice_credit_applied_cents(invoice_id) do
    net_cents =
      FinanceCreditLedgerEntry
      |> where([entry], entry.finance_invoice_id == ^invoice_id)
      |> where([entry], entry.entry_type in ["invoice_offset", "reversal"])
      |> where([entry], is_nil(entry.deleted_at))
      |> Repo.aggregate(:sum, :amount_cents)
      |> case do
        nil -> 0
        value -> value
      end

    max(-net_cents, 0)
  end

  defp payment_reversed_cents(payment_id) do
    FinancePaymentReversal
    |> where([reversal], reversal.membership_payment_id == ^payment_id)
    |> where([reversal], is_nil(reversal.deleted_at))
    |> Repo.aggregate(:sum, :amount_cents)
    |> case do
      nil -> 0
      value -> value
    end
  end

  defp invoice_payment_reversed_cents(invoice_id) do
    FinancePaymentReversal
    |> where([reversal], reversal.finance_invoice_id == ^invoice_id)
    |> where([reversal], is_nil(reversal.deleted_at))
    |> Repo.aggregate(:sum, :amount_cents)
    |> case do
      nil -> 0
      value -> value
    end
  end

  defp credit_entry_reversed_cents(entry_id) do
    FinanceCreditLedgerEntry
    |> where([entry], entry.reversed_credit_ledger_entry_id == ^entry_id)
    |> where([entry], entry.amount_cents > 0)
    |> where([entry], is_nil(entry.deleted_at))
    |> Repo.aggregate(:sum, :amount_cents)
    |> case do
      nil -> 0
      value -> value
    end
  end

  defp validate_payment_credit_reversals(payment_id) do
    outstanding =
      FinanceCreditLedgerEntry
      |> where([entry], entry.membership_payment_id == ^payment_id)
      |> where([entry], entry.amount_cents < 0)
      |> where([entry], is_nil(entry.deleted_at))
      |> Repo.all()
      |> Enum.filter(fn entry ->
        credit_entry_reversed_cents(entry.id) < abs(entry.amount_cents)
      end)

    if outstanding == [], do: :ok, else: {:error, :credit_reversal_required}
  end

  defp invoice_balance_due(invoice_id) do
    case FinanceInvoice |> tenant_scope() |> Repo.get(invoice_id) do
      nil ->
        0

      %FinanceInvoice{status: "void"} ->
        0

      %FinanceInvoice{deleted_at: deleted_at} when not is_nil(deleted_at) ->
        0

      %FinanceInvoice{} = invoice ->
        max(
          invoice.total_cents - invoice_paid_cents(invoice.id) -
            invoice_credit_applied_cents(invoice.id),
          0
        )
    end
  end

  defp billable_invoice?(%FinanceInvoice{} = invoice),
    do: get_in(invoice.params || %{}, ["document_kind"]) != "receipt"

  defp refresh_invoice_and_entitlement(nil, membership_id) do
    refresh_entitlement_snapshot(membership_id)
  end

  defp refresh_invoice_and_entitlement(invoice_id, membership_id) do
    _ = refresh_invoice_status(invoice_id)
    refresh_entitlement_snapshot(membership_id)
  end

  defp refresh_invoice_status(invoice_id) do
    Repo.transaction(fn ->
      case locked_invoice(invoice_id) do
        nil ->
          Repo.rollback(:not_found)

        %FinanceInvoice{status: status} = invoice when status in ["draft", "void"] ->
          invoice

        %FinanceInvoice{} = invoice ->
          next_status =
            InvoiceLifecycle.status(
              invoice.total_cents,
              invoice_paid_cents(invoice.id),
              invoice_credit_applied_cents(invoice.id),
              invoice.due_date,
              GymClock.today(),
              invoice.status,
              invoice.params
            )

          invoice
          |> FinanceInvoice.changeset(%{status: next_status})
          |> Repo.update()
          |> case do
            {:ok, updated_invoice} -> updated_invoice
            {:error, reason} -> Repo.rollback(reason)
          end
      end
    end)
  end

  defp constraint_error?(%Ecto.Changeset{} = changeset, constraint_name) do
    Enum.any?(changeset.errors, fn {_field, {_message, metadata}} ->
      to_string(metadata[:constraint_name]) == constraint_name
    end)
  end

  defp entitlement_for_membership(%Membership{} = membership) do
    open_statuses = InvoiceLifecycle.blocking_invoice_statuses()

    blocking_invoices =
      FinanceInvoice
      |> where([invoice], invoice.membership_id == ^membership.id)
      |> where([invoice], invoice.status in ^open_statuses)
      |> where([invoice], is_nil(invoice.deleted_at))
      |> Repo.all()

    today = GymClock.today()

    open_invoice_count =
      Enum.count(blocking_invoices, fn invoice -> invoice_balance_due(invoice.id) > 0 end)

    overdue_invoices =
      Enum.filter(blocking_invoices, fn invoice ->
        invoice_balance_due(invoice.id) > 0 and invoice.due_date != nil and
          Date.compare(today, invoice.due_date) == :gt
      end)

    overdue_invoice_count = length(overdue_invoices)

    earliest_overdue_due_date =
      overdue_invoices |> Enum.map(& &1.due_date) |> Enum.min(Date, fn -> nil end)

    # ADR-098: a beneficiary of a shared membership holds it as well.
    shared_ids = beneficiary_subscription_ids(membership.id)

    active_subscription? =
      MembershipPackageSubscription
      |> where(
        [subscription],
        subscription.membership_id == ^membership.id or subscription.id in ^shared_ids
      )
      |> where(
        [subscription],
        subscription.status in ^InvoiceLifecycle.active_subscription_statuses()
      )
      |> where([subscription], is_nil(subscription.starts_on) or subscription.starts_on <= ^today)
      |> where([subscription], is_nil(subscription.ends_on) or subscription.ends_on >= ^today)
      |> Repo.exists?()

    grace_days = subscription_grace_days()

    lapsed_subscription_ends_on =
      if active_subscription?,
        do: nil,
        else: lapsed_subscription_ends_on(membership.id, today, grace_days)

    derived =
      InvoiceLifecycle.entitlement(%{
        membership_status: membership.status,
        membership_expires_on: membership.expires_on,
        active_subscription?: active_subscription?,
        open_invoice_count: open_invoice_count,
        overdue_invoice_count: overdue_invoice_count,
        earliest_overdue_due_date: earliest_overdue_due_date,
        lapsed_subscription_ends_on: lapsed_subscription_ends_on,
        grace_days: grace_days,
        today: today
      })

    %{
      status: derived.status,
      source: derived.source,
      expires_on: derived.expires_on,
      grace_until: derived.grace_until,
      open_invoice_count: open_invoice_count,
      overdue_invoice_count: overdue_invoice_count,
      credit_balance_cents: credit_balance(membership.id),
      updated_at: membership.entitlement_updated_at
    }
  end

  defp refresh_entitlement_snapshot(nil), do: :ok

  defp refresh_entitlement_snapshot(membership_id) do
    case Membership |> tenant_scope() |> Repo.get(membership_id) do
      nil ->
        :ok

      %Membership{} = membership ->
        entitlement = entitlement_for_membership(membership)

        membership
        |> Membership.changeset(%{
          entitlement_status: entitlement.status,
          entitlement_source: entitlement.source,
          entitlement_expires_on: entitlement.expires_on,
          entitlement_updated_at: utc_now()
        })
        |> Repo.update()

        :ok
    end
  end

  defp credit_balance(membership_id) do
    FinanceCreditLedgerEntry
    |> where([entry], entry.membership_id == ^membership_id)
    |> where([entry], is_nil(entry.deleted_at))
    |> Repo.aggregate(:sum, :amount_cents)
    |> case do
      nil -> 0
      value -> value
    end
  end

  defp remaining_payment_credit_capacity(%MembershipPayment{} = payment) do
    applied_cents =
      FinanceCreditLedgerEntry
      |> where([entry], entry.membership_payment_id == ^payment.id)
      |> where([entry], entry.amount_cents < 0)
      |> where([entry], is_nil(entry.deleted_at))
      |> Repo.aggregate(:sum, :amount_cents)
      |> case do
        nil -> 0
        value -> abs(value)
      end

    max(payment.amount_cents - applied_cents, 0)
  end

  defp get_reward_event(%ReferralReward{} = reward) do
    case ReferralEvent |> tenant_scope() |> Repo.get(reward.referral_event_id) do
      nil -> {:error, :not_found}
      %ReferralEvent{} = event -> {:ok, event}
    end
  end

  defp validate_reward_event_status(event, status) when status in ["approved", "applied"] do
    if event.status in ["approved", "applied"] do
      :ok
    else
      {:error, :referral_event_not_approved}
    end
  end

  defp validate_reward_event_status(_event, _status), do: :ok

  @impl true
  def refresh_aggregates do
    with {:ok, _} <- refresh_view("finance_aggregates") do
      :ok
    end
  end

  defp list_subscriptions(membership_id) do
    MembershipPackageSubscription
    |> where([subscription], subscription.membership_id == ^membership_id)
    |> order_by([subscription], desc: subscription.inserted_at)
    |> Repo.all()
    |> Enum.map(&normalize_subscription/1)
  end

  defp effective_subscriptions_for_package(package_id) do
    today = GymClock.today()

    MembershipPackageSubscription
    |> where([subscription], subscription.membership_package_id == ^package_id)
    |> where([subscription], subscription.status == "active")
    |> where([subscription], is_nil(subscription.starts_on) or subscription.starts_on <= ^today)
    |> where([subscription], is_nil(subscription.ends_on) or subscription.ends_on >= ^today)
    |> order_by([subscription], desc: subscription.starts_on, desc: subscription.inserted_at)
    |> lock("FOR UPDATE")
    |> Repo.all()
    |> Enum.uniq_by(& &1.membership_id)
    |> Enum.filter(fn subscription ->
      case renewal_subscription(subscription.membership_id, nil) do
        %{id: id} -> id == subscription.id
        nil -> false
      end
    end)
  end

  defp requested_inactive?(params) when is_map(params) do
    Map.get(params, "active", Map.get(params, :active)) == false
  end

  defp member_search_summaries([]), do: %{}

  defp member_search_summaries(memberships) do
    membership_ids = Enum.map(memberships, & &1.id)

    subscriptions_by_membership_id =
      MembershipPackageSubscription
      |> where([subscription], subscription.membership_id in ^membership_ids)
      |> order_by([subscription], desc: subscription.inserted_at)
      |> Repo.all()
      |> Enum.group_by(& &1.membership_id, &normalize_subscription/1)

    last_payments_by_membership_id =
      from(p in MembershipPayment,
        where: p.membership_id in ^membership_ids,
        where: is_nil(p.deleted_at),
        distinct: p.membership_id,
        order_by: [asc: p.membership_id, desc: p.inserted_at],
        select: %{
          membership_id: p.membership_id,
          paid_on: p.paid_on,
          amount_cents: p.amount_cents
        }
      )
      |> Repo.all()
      |> Map.new(&{&1.membership_id, &1})

    outstanding_by_membership_id =
      outstanding_balance_per_membership(membership_ids)

    Map.new(memberships, fn membership ->
      subscriptions = Map.get(subscriptions_by_membership_id, membership.id, [])
      last_payment = Map.get(last_payments_by_membership_id, membership.id)
      credit_balance_cents = credit_balance(membership.id)
      outstanding_cents = Map.get(outstanding_by_membership_id, membership.id, 0)

      {membership.user_id,
       %{
         membership: normalize_membership(membership),
         package_subscriptions: subscriptions,
         active_package_subscription:
           Enum.find(
             subscriptions,
             &(&1.status in InvoiceLifecycle.active_subscription_statuses())
           ),
         credit_balance: credit_balance_cents,
         credit_balance_cents: credit_balance_cents,
         outstanding_balance_cents: outstanding_cents,
         last_payment_on: last_payment && last_payment.paid_on,
         last_payment_amount_cents: last_payment && last_payment.amount_cents
       }}
    end)
  end

  defp maybe_filter_user_ids(query, []), do: where(query, [membership], is_nil(membership.id))

  defp maybe_filter_user_ids(query, user_ids) when is_list(user_ids) do
    where(query, [membership], membership.user_id in ^user_ids)
  end

  defp maybe_filter_membership_status(query, value) when value in [nil, "", "all"], do: query

  defp maybe_filter_membership_status(query, value) do
    where(query, [membership], membership.status == ^value)
  end

  defp maybe_filter_user_type(query, value) when value in [nil, "", "all"], do: query

  defp maybe_filter_user_type(query, value) do
    where(query, [membership], membership.user_type_snapshot == ^value)
  end

  defp maybe_filter_package_code(query, value) when value in [nil, "", "all"], do: query

  defp maybe_filter_package_code(query, value) do
    where(
      query,
      [membership],
      exists(
        from(subscription in MembershipPackageSubscription,
          where: subscription.membership_id == parent_as(:membership).id,
          where: subscription.package_code_snapshot == ^value,
          select: 1
        )
      )
    )
  end

  defp maybe_filter_package_family(query, value) when value in [nil, "", "all"], do: query

  defp maybe_filter_package_family(query, value) do
    where(
      query,
      [membership],
      exists(
        from(subscription in MembershipPackageSubscription,
          where: subscription.membership_id == parent_as(:membership).id,
          where: subscription.package_family_snapshot == ^value,
          select: 1
        )
      )
    )
  end

  defp active_subscription_for_membership(membership_id) do
    case renewal_subscription(membership_id, nil) do
      nil -> nil
      subscription -> normalize_subscription(subscription)
    end
  end

  defp list_payments(membership_id) do
    MembershipPayment
    |> where([payment], payment.membership_id == ^membership_id)
    |> where([payment], is_nil(payment.deleted_at))
    |> order_by([payment], desc: payment.paid_on, desc: payment.inserted_at)
    |> Repo.all()
    |> Enum.map(&normalize_payment/1)
  end

  defp list_redemptions(membership_id) do
    PromotionRedemption
    |> where([redemption], redemption.membership_id == ^membership_id)
    |> order_by([redemption], desc: redemption.redeemed_at)
    |> Repo.all()
    |> Enum.map(&normalize_promotion_redemption/1)
  end

  # ADR-186 §8: a promotion valid at some branches applies to a subscription
  # whose package is valid at one of them (or everywhere).
  defp validate_campaign_branches(campaign_id, _params) when not is_binary(campaign_id), do: :ok

  defp validate_campaign_branches(campaign_id, params) do
    with %PromotionCampaign{all_locations: false, location_ids: ids} <-
           PromotionCampaign |> tenant_scope() |> Repo.get(campaign_id),
         subscription_id when is_binary(subscription_id) <-
           params["membership_package_subscription_id"],
         %MembershipPackageSubscription{params_snapshot: snapshot} <-
           Repo.get(MembershipPackageSubscription, subscription_id) do
      case PackageContract.fields_from_params(snapshot || %{})["facility.location_ids"] do
        package_ids when is_list(package_ids) and package_ids != [] ->
          if Enum.any?(package_ids, &(&1 in ids)),
            do: :ok,
            else: {:error, :promotion_location_not_included}

        _everywhere ->
          :ok
      end
    else
      _not_limited -> :ok
    end
  end

  defp build_redemption_params(membership, params) do
    case find_promotion_code(params) do
      {:ok, %PromotionCode{} = code} ->
        with :ok <- validate_campaign_branches(code.promotion_campaign_id, params) do
          redemption_from_code(membership, params, code)
        end

      {:error, reason} ->
        {:error, reason}

      :not_requested ->
        with :ok <- validate_campaign_branches(params["promotion_campaign_id"], params) do
          manual_redemption(membership, params)
        end
    end
  end

  defp redemption_from_code(membership, params, code) do
    {:ok,
     params
     |> Map.merge(%{
       "promotion_campaign_id" => code.promotion_campaign_id,
       "promotion_code_id" => code.id,
       "membership_id" => membership.id,
       "discount_type_snapshot" => code.discount_type,
       "discount_value_snapshot" => code.discount_value
     })
     |> Map.put_new("redeemed_at", utc_now())}
  end

  defp manual_redemption(membership, params) do
    if is_binary(params["promotion_campaign_id"]) do
      with %PromotionCampaign{} = campaign <-
             PromotionCampaign |> tenant_scope() |> Repo.get(params["promotion_campaign_id"]),
           :ok <- validate_campaign_active(campaign),
           :ok <- validate_campaign_window(campaign, GymClock.today()),
           {:ok, {discount_type, discount_value}} <-
             PromotionRedemptionPolicy.validate_manual_discount(
               params["discount_type_snapshot"],
               params["discount_value_snapshot"]
             ) do
        {:ok,
         params
         |> Map.put("promotion_campaign_id", campaign.id)
         |> Map.put("membership_id", membership.id)
         |> Map.put("discount_type_snapshot", discount_type)
         |> Map.put("discount_value_snapshot", discount_value)
         |> Map.put_new("redeemed_at", utc_now())}
      else
        nil -> {:error, :not_found}
        {:error, reason} -> {:error, reason}
      end
    else
      {:error, :bad_request}
    end
  end

  defp validate_payment_links(membership_id, params) do
    with :ok <-
           validate_subscription_link(
             membership_id,
             params["membership_package_subscription_id"],
             :membership_package_subscription_id
           ),
         :ok <- validate_invoice_link(membership_id, params["finance_invoice_id"]) do
      :ok
    end
  end

  defp validate_invoice_subscription_link(membership_id, params) do
    validate_subscription_link(
      membership_id,
      params["membership_package_subscription_id"],
      :membership_package_subscription_id
    )
  end

  defp validate_invoice_line_subscription_links(membership_id, line_params) do
    Enum.reduce_while(line_params, :ok, fn line, :ok ->
      case validate_subscription_link(
             membership_id,
             line["membership_package_subscription_id"],
             :membership_package_subscription_id
           ) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp validate_redemption_links(membership_id, params) do
    with :ok <-
           validate_subscription_link(
             membership_id,
             params["membership_package_subscription_id"],
             :membership_package_subscription_id
           ),
         :ok <- validate_payment_link(membership_id, params["membership_payment_id"]) do
      :ok
    end
  end

  defp validate_subscription_link(_membership_id, nil, _field), do: :ok
  defp validate_subscription_link(_membership_id, "", _field), do: :ok

  defp validate_subscription_link(membership_id, subscription_id, field) do
    case MembershipPackageSubscription |> tenant_scope() |> Repo.get(subscription_id) do
      nil ->
        {:error, :not_found}

      %MembershipPackageSubscription{} = subscription ->
        MembershipLinks.validate_optional_link(field, membership_id, subscription.membership_id)
    end
  end

  defp validate_payment_link(_membership_id, nil), do: :ok
  defp validate_payment_link(_membership_id, ""), do: :ok

  defp validate_payment_link(membership_id, payment_id) do
    case Repo.get(MembershipPayment, payment_id) do
      nil ->
        {:error, :not_found}

      %MembershipPayment{deleted_at: deleted_at} when not is_nil(deleted_at) ->
        {:error, :not_found}

      %MembershipPayment{} = payment ->
        MembershipLinks.validate_optional_link(
          :membership_payment_id,
          membership_id,
          payment.membership_id
        )
    end
  end

  defp validate_invoice_link(_membership_id, nil), do: :ok
  defp validate_invoice_link(_membership_id, ""), do: :ok

  defp validate_invoice_link(membership_id, invoice_id) do
    case FinanceInvoice |> tenant_scope() |> Repo.get(invoice_id) do
      nil ->
        {:error, :not_found}

      %FinanceInvoice{deleted_at: deleted_at} when not is_nil(deleted_at) ->
        {:error, :not_found}

      %FinanceInvoice{} = invoice ->
        MembershipLinks.validate_optional_link(
          :finance_invoice_id,
          membership_id,
          invoice.membership_id
        )
    end
  end

  defp validate_invoice_payment_application(%{"finance_invoice_id" => invoice_id} = params)
       when is_binary(invoice_id) and invoice_id != "" do
    case locked_invoice(invoice_id) do
      nil ->
        {:error, :not_found}

      %FinanceInvoice{} = invoice ->
        InvoiceLifecycle.validate_payment_application(
          invoice.status,
          parse_integer(params["amount_cents"], 0),
          invoice_balance_due(invoice.id)
        )
    end
  end

  defp validate_invoice_payment_application(_params), do: :ok

  defp referral_membership_user_id(nil), do: {:error, :referral_membership_required}
  defp referral_membership_user_id(""), do: {:error, :referral_membership_required}

  defp referral_membership_user_id(membership_id) do
    case Membership |> tenant_scope() |> Repo.get(membership_id) do
      nil -> {:error, :not_found}
      %Membership{} = membership -> {:ok, membership.user_id}
    end
  end

  defp referral_reward_exists?(referral_event_id) do
    Repo.exists?(
      from(reward in ReferralReward, where: reward.referral_event_id == ^referral_event_id)
    )
  end

  defp derive_membership_status(params) do
    Map.put(
      params,
      "status",
      MembershipLifecycle.derive_status(
        params["status"],
        params["starts_on"],
        params["expires_on"],
        GymClock.today()
      )
    )
  end

  @impl true
  def package_location_scopes do
    today = GymClock.today()

    MembershipPackageSubscription
    |> join(:inner, [subscription], membership in Membership,
      on: membership.id == subscription.membership_id
    )
    |> where([subscription], subscription.status in ["active", "paused"])
    |> where([subscription], is_nil(subscription.ends_on) or subscription.ends_on >= ^today)
    |> select([subscription, membership], {membership.user_id, subscription.params_snapshot})
    |> Repo.all()
    |> Enum.reduce(%{}, fn {user_id, snapshot}, acc ->
      scope =
        case PackageContract.fields_from_params(snapshot || %{})["facility.location_ids"] do
          ids when is_list(ids) and ids != [] -> ids
          _all -> :all
        end

      Map.update(acc, user_id, scope, &union_scope(&1, scope))
    end)
  end

  defp union_scope(:all, _scope), do: :all
  defp union_scope(_scope, :all), do: :all
  defp union_scope(left, right), do: Enum.uniq(left ++ right)

  # ADR-186 §7: `user_ids` (a list) restricts a report to people; absent, the
  # report covers the whole business.
  defp branch_users(%{"user_ids" => users}) when is_list(users), do: users
  defp branch_users(_params), do: nil

  defp branch_location_ids(%{"location_ids" => ids}) when is_list(ids), do: ids
  defp branch_location_ids(_params), do: []

  defp for_users(query, nil), do: query
  defp for_users(query, users), do: where(query, [record], record.user_id in ^users)

  defp for_user_memberships(query, nil), do: query

  defp for_user_memberships(query, users) do
    memberships =
      from(membership in Membership, where: membership.user_id in ^users, select: membership.id)

    where(query, [record], record.membership_id in subquery(memberships))
  end

  defp monthly_payment_revenue(scope, first_month) do
    rows =
      payment_rows()
      |> for_payment_scope(scope)
      |> where(
        [payment],
        is_nil(payment.deleted_at) and payment.paid_on >= type(^first_month, :date)
      )
      |> where([payment], payment.payment_status in ["paid", "pending"])
      |> select([payment], {payment.paid_on, payment.payment_status, payment.amount_cents})
      |> Repo.all()

    totals =
      Enum.reduce(rows, %{}, fn {paid_on, status, amount}, acc ->
        key = if status == "paid", do: :paid_revenue_cents, else: :pending_revenue_cents

        Map.update(
          acc,
          Date.beginning_of_month(paid_on),
          Map.put(%{paid_revenue_cents: 0, pending_revenue_cents: 0}, key, amount),
          &Map.update!(&1, key, fn total -> total + amount end)
        )
      end)

    Enum.map(0..23, fn offset ->
      month = Date.shift(first_month, month: offset)

      Map.merge(
        %{period_start: month},
        Map.get(totals, month, %{paid_revenue_cents: 0, pending_revenue_cents: 0})
      )
    end)
  end

  defp active_membership_count(users) do
    today = GymClock.today()

    Membership
    |> for_users(users)
    |> where([membership], membership.status in ["active", "trial", "expiring", "comped"])
    |> where([membership], is_nil(membership.expires_on) or membership.expires_on >= ^today)
    |> Repo.aggregate(:count)
  end

  defp find_promotion_code(%{"promotion_code_id" => promotion_code_id})
       when is_binary(promotion_code_id) do
    case locked_promotion_code_by_id(promotion_code_id) do
      %PromotionCode{} = code -> validate_promotion_code(code)
      nil -> {:error, :not_found}
    end
  end

  defp find_promotion_code(%{"promotion_code" => promotion_code})
       when is_binary(promotion_code) do
    normalized_code =
      promotion_code
      |> String.trim()
      |> String.upcase()

    case locked_promotion_code_by_code(normalized_code) do
      %PromotionCode{} = code -> validate_promotion_code(code)
      nil -> {:error, :not_found}
    end
  end

  defp find_promotion_code(_params), do: :not_requested

  defp validate_promotion_code(%PromotionCode{active: false}),
    do: {:error, :promotion_code_inactive}

  defp validate_promotion_code(%PromotionCode{} = code) do
    with %PromotionCampaign{} = campaign <-
           PromotionCampaign |> tenant_scope() |> Repo.get(code.promotion_campaign_id),
         :ok <- validate_campaign_active(campaign),
         :ok <- validate_campaign_window(campaign, GymClock.today()),
         :ok <- validate_code_redemption_limit(code) do
      {:ok, code}
    else
      nil -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  defp validate_campaign_active(%PromotionCampaign{active: true}), do: :ok
  defp validate_campaign_active(%PromotionCampaign{}), do: {:error, :promotion_campaign_inactive}

  defp validate_campaign_window(%PromotionCampaign{} = campaign, today) do
    cond do
      campaign.starts_on && Date.compare(today, campaign.starts_on) == :lt ->
        {:error, :promotion_campaign_not_started}

      campaign.ends_on && Date.compare(today, campaign.ends_on) == :gt ->
        {:error, :promotion_campaign_expired}

      true ->
        :ok
    end
  end

  defp validate_code_redemption_limit(%PromotionCode{max_redemptions: nil}), do: :ok

  defp validate_code_redemption_limit(%PromotionCode{} = code) do
    redemption_count =
      PromotionRedemption
      |> where([redemption], redemption.promotion_code_id == ^code.id)
      |> Repo.aggregate(:count)

    if redemption_count < code.max_redemptions do
      :ok
    else
      {:error, :promotion_code_max_redemptions_reached}
    end
  end

  defp validate_package_active(%MembershipPackage{active: true}), do: :ok
  defp validate_package_active(%MembershipPackage{}), do: {:error, :package_inactive}

  # ADR-156: a reward follows the programme the referral was made under, even
  # when the box has since switched to another one.
  defp event_referral_program(nil), do: {:error, :referral_program_required}

  defp event_referral_program(program_id) do
    case ReferralProgram |> tenant_scope() |> Repo.get(program_id) do
      nil -> {:error, :not_found}
      %ReferralProgram{} = program -> {:ok, program}
    end
  end

  defp active_referral_program(nil), do: {:error, :referral_program_required}
  defp active_referral_program(""), do: {:error, :referral_program_required}

  defp active_referral_program(program_id) do
    case ReferralProgram |> tenant_scope() |> Repo.get(program_id) do
      nil -> {:error, :not_found}
      %ReferralProgram{active: false} -> {:error, :referral_program_inactive}
      %ReferralProgram{} = program -> {:ok, program}
    end
  end

  defp locked_promotion_code_by_id(id) do
    PromotionCode
    |> where([code], code.id == ^id)
    |> lock("FOR UPDATE")
    |> Repo.one()
  end

  defp locked_promotion_code_by_code(value) do
    PromotionCode
    |> where([code], code.code == ^value)
    |> lock("FOR UPDATE")
    |> Repo.one()
  end

  defp total_paid_revenue_cents(since, scope) do
    since
    |> paid_revenue_base(scope)
    |> select(
      [payment, _invoice, reversal],
      sum(
        fragment("GREATEST(? - COALESCE(?, 0), 0)", payment.amount_cents, reversal.reversed_cents)
      )
    )
    |> Repo.one()
    |> case do
      nil -> 0
      value -> db_integer(value)
    end
  end

  # The paid payments behind `paid_revenue_cents`: paid, not deleted, on or
  # after `since`, on a live invoice (or none), joined to their reversals.
  # The headline figure and its per-stream breakdown (ADR-192 §2) both read
  # this one query, so the breakdown always adds up to the headline.
  defp paid_revenue_base(since, scope) do
    payment_reversals =
      from(reversal in FinancePaymentReversal,
        where: is_nil(reversal.deleted_at),
        group_by: reversal.membership_payment_id,
        select: %{
          membership_payment_id: reversal.membership_payment_id,
          reversed_cents: sum(reversal.amount_cents)
        }
      )

    payment_rows()
    |> for_payment_scope(scope)
    |> where([payment], payment.payment_status == "paid")
    |> where([payment], payment.paid_on >= type(^since, :date))
    |> where([payment], is_nil(payment.deleted_at))
    |> join(:left, [payment], invoice in FinanceInvoice,
      on: invoice.id == payment.finance_invoice_id
    )
    |> where([payment, invoice], is_nil(payment.finance_invoice_id) or is_nil(invoice.deleted_at))
    |> join(:left, [payment, _invoice], reversal in subquery(payment_reversals),
      on: reversal.membership_payment_id == payment.id
    )
  end

  # The payment rows of the revenue reads, with ADR-190's lineage columns.
  # Read from the table rather than the schema so the reads do not depend on
  # which writer maps those columns; Postgres inlines the subquery, so the
  # plan is the plain table scan of before.
  defp payment_rows do
    from(
      payment in subquery(
        from(payment in "membership_payments",
          select: %{
            id: type(payment.id, :binary_id),
            membership_id: type(payment.membership_id, :binary_id),
            membership_package_subscription_id:
              type(payment.membership_package_subscription_id, :binary_id),
            finance_invoice_id: type(payment.finance_invoice_id, :binary_id),
            amount_cents: type(payment.amount_cents, :integer),
            paid_on: type(payment.paid_on, :date),
            payment_status: type(payment.payment_status, :string),
            deleted_at: type(payment.deleted_at, :utc_datetime_usec),
            revenue_stream: type(payment.revenue_stream, :string),
            source_type: type(payment.source_type, :string),
            source_id: type(payment.source_id, :binary_id)
          }
        )
      )
    )
  end

  # ADR-192 §2: net paid revenue per revenue stream, from the same payments,
  # window and reversal netting as `paid_revenue_cents`. The database groups
  # by what the classifier looks at (a handful of groups however many
  # payments there are); `RevenueBreakdown` names each group's stream.
  defp revenue_by_stream(since, scope) do
    since
    |> paid_revenue_base(scope)
    |> stream_inputs_join()
    |> group_by([payment, invoice, _reversal, _subscription, package], [
      payment.revenue_stream,
      package.package_type,
      fragment("(?->>'idempotency_key')", invoice.params),
      fragment(
        "EXISTS (SELECT 1 FROM finance_invoice_lines line WHERE line.finance_invoice_id = ? AND line.revenue_stream = 'event')",
        payment.finance_invoice_id
      )
    ])
    |> select([payment, invoice, reversal, _subscription, package], {
      payment.revenue_stream,
      package.package_type,
      fragment("(?->>'idempotency_key')", invoice.params),
      fragment(
        "EXISTS (SELECT 1 FROM finance_invoice_lines line WHERE line.finance_invoice_id = ? AND line.revenue_stream = 'event')",
        payment.finance_invoice_id
      ),
      sum(payment.amount_cents),
      sum(
        fragment("GREATEST(? - COALESCE(?, 0), 0)", payment.amount_cents, reversal.reversed_cents)
      ),
      count(payment.id)
    })
    |> Repo.all()
    |> Enum.map(fn {stream, package_type, reference, event_line?, gross, net, count} ->
      {stream_fact(stream, package_type, reference, event_line?), db_integer(gross),
       db_integer(net), count}
    end)
    |> RevenueBreakdown.breakdown()
  end

  # Monthly net paid revenue per stream over the 24 months of
  # `monthly_revenue`, bucketed by `paid_on` (the gym-local business date).
  defp monthly_revenue_by_stream(first_month, scope) do
    first_month
    |> paid_revenue_base(scope)
    |> stream_inputs_join()
    |> group_by([payment, invoice, _reversal, _subscription, package], [
      fragment("date_trunc('month', ?)::date", payment.paid_on),
      payment.revenue_stream,
      package.package_type,
      fragment("(?->>'idempotency_key')", invoice.params),
      fragment(
        "EXISTS (SELECT 1 FROM finance_invoice_lines line WHERE line.finance_invoice_id = ? AND line.revenue_stream = 'event')",
        payment.finance_invoice_id
      )
    ])
    |> select([payment, invoice, reversal, _subscription, package], {
      fragment("date_trunc('month', ?)::date", payment.paid_on),
      payment.revenue_stream,
      package.package_type,
      fragment("(?->>'idempotency_key')", invoice.params),
      fragment(
        "EXISTS (SELECT 1 FROM finance_invoice_lines line WHERE line.finance_invoice_id = ? AND line.revenue_stream = 'event')",
        payment.finance_invoice_id
      ),
      sum(
        fragment("GREATEST(? - COALESCE(?, 0), 0)", payment.amount_cents, reversal.reversed_cents)
      )
    })
    |> Repo.all()
    |> Enum.group_by(&elem(&1, 0), fn {_month, stream, type, reference, event_line?, net} ->
      {stream_fact(stream, type, reference, event_line?), 0, db_integer(net), 0}
    end)
    |> then(fn by_month ->
      Enum.map(0..23, fn offset ->
        month = Date.shift(first_month, month: offset)
        %{net_by_stream: net} = RevenueBreakdown.breakdown(Map.get(by_month, month, []))
        %{period_start: month, revenue_by_stream: net}
      end)
    end)
  end

  defp stream_inputs_join(query) do
    query
    |> join(:left, [payment, invoice, _reversal], subscription in MembershipPackageSubscription,
      on:
        subscription.id ==
          coalesce(
            payment.membership_package_subscription_id,
            invoice.membership_package_subscription_id
          )
    )
    |> join(:left, [_payment, _invoice, _reversal, subscription], package in MembershipPackage,
      on: package.id == subscription.membership_package_id
    )
  end

  defp stream_fact(stream, package_type, reference, event_line?) do
    %{
      explicit_stream: stream,
      package_type: package_type,
      reference: reference,
      charge_category: if(event_line?, do: "event")
    }
  end

  # ADR-186 §7 and ADR-192 §2: under a branch filter a payment belongs to the
  # people whose home branch is in the filter, except shop payments, which
  # belong to the branch of the order they pay (a walk-in has no home
  # branch, and a member may shop at another branch). Before the shop no
  # payment is `shop`, so every older figure is exactly what it was.
  defp for_payment_scope(query, %{users: nil}), do: query

  defp for_payment_scope(query, %{users: users, location_ids: location_ids}) do
    memberships =
      from(membership in Membership, where: membership.user_id in ^users, select: membership.id)

    shop_location_ids = normalize_uuid_list(location_ids)

    where(
      query,
      [payment],
      (payment.revenue_stream != "shop" and payment.membership_id in subquery(memberships)) or
        (payment.revenue_stream == "shop" and payment.source_type == "shop_order" and
           fragment(
             "EXISTS (SELECT 1 FROM shop_orders shop_order WHERE shop_order.id = ? AND shop_order.pickup_location_id = ANY(?))",
             payment.source_id,
             type(^shop_location_ids, {:array, :binary_id})
           ))
    )
  end

  defp total_credit_balance_cents(users) do
    FinanceCreditLedgerEntry
    |> for_users(users)
    |> where([entry], is_nil(entry.deleted_at))
    |> Repo.aggregate(:sum, :amount_cents)
    |> case do
      nil -> 0
      value -> value
    end
  end

  defp total_invoice_credit_offset_cents(users) do
    FinanceCreditLedgerEntry
    |> for_users(users)
    |> where([entry], not is_nil(entry.finance_invoice_id))
    |> where([entry], entry.source_type in ["invoice_offset", "reversal"])
    |> where([entry], is_nil(entry.deleted_at))
    |> select(
      [entry],
      fragment(
        "ABS(LEAST(COALESCE(SUM(CASE WHEN ? < 0 AND ? = 'invoice_offset' THEN ? WHEN ? = 'reversal' THEN ? ELSE 0 END), 0), 0))",
        entry.amount_cents,
        entry.source_type,
        entry.amount_cents,
        entry.source_type,
        entry.amount_cents
      )
    )
    |> Repo.one()
    |> case do
      nil -> 0
      value -> db_integer(value)
    end
  end

  defp renewal_invoice_metrics(users) do
    issued_count =
      FinanceInvoice
      |> for_users(users)
      |> where([invoice], invoice.invoice_type == "renewal")
      |> where([invoice], invoice.status in ["issued", "partially_paid", "paid", "overdue"])
      |> where([invoice], is_nil(invoice.deleted_at))
      |> Repo.aggregate(:count)

    paid_count =
      FinanceInvoice
      |> for_users(users)
      |> where([invoice], invoice.invoice_type == "renewal")
      |> where([invoice], invoice.status == "paid")
      |> where([invoice], is_nil(invoice.deleted_at))
      |> Repo.aggregate(:count)

    conversion_percent =
      if issued_count == 0 do
        0.0
      else
        Float.round(paid_count / issued_count * 100, 1)
      end

    %{
      issued_count: issued_count,
      paid_count: paid_count,
      conversion_percent: conversion_percent
    }
  end

  defp total_outstanding_invoice_balance_cents(users) do
    FinanceInvoice
    |> for_users(users)
    |> where([invoice], invoice.status in ["issued", "partially_paid", "overdue"])
    |> where([invoice], is_nil(invoice.deleted_at))
    |> Repo.all()
    |> Enum.reduce(0, fn invoice, acc -> acc + invoice_balance_due(invoice.id) end)
  end

  defp total_overdue_invoice_balance_cents(users) do
    FinanceInvoice
    |> for_users(users)
    |> where([invoice], invoice.status in ["issued", "partially_paid", "overdue"])
    |> where([invoice], not is_nil(invoice.due_date) and invoice.due_date < ^GymClock.today())
    |> where([invoice], is_nil(invoice.deleted_at))
    |> Repo.all()
    |> Enum.reduce(0, fn invoice, acc -> acc + invoice_balance_due(invoice.id) end)
  end

  defp list_pending_payments(limit, users) do
    MembershipPayment
    |> for_user_memberships(users)
    |> where([payment], payment.payment_status in ["pending", "failed"])
    |> where([payment], is_nil(payment.deleted_at))
    |> order_by([payment], desc: payment.paid_on, desc: payment.inserted_at)
    |> limit(^limit)
    |> Repo.all()
    |> Enum.map(&normalize_payment/1)
  end

  defp list_overdue_invoices(limit, users) do
    FinanceInvoice
    |> for_users(users)
    |> where([invoice], invoice.status in ["issued", "partially_paid", "overdue"])
    |> where([invoice], not is_nil(invoice.due_date) and invoice.due_date < ^GymClock.today())
    |> where([invoice], is_nil(invoice.deleted_at))
    |> order_by([invoice], asc: invoice.due_date)
    |> limit(^limit)
    |> Repo.all()
    |> Enum.map(&normalize_invoice_with_computed_status/1)
    |> Enum.filter(&(&1.balance_due_cents > 0))
  end

  defp list_pending_referral_events(limit, users) do
    ReferralEvent
    |> where([event], event.status in ["pending", "approved"])
    |> then(fn query ->
      if is_list(users),
        do:
          where(
            query,
            [event],
            event.referrer_user_id in ^users or event.referred_user_id in ^users
          ),
        else: query
    end)
    |> order_by([event], asc: event.inserted_at)
    |> limit(^limit)
    |> Repo.all()
    |> Enum.map(&normalize_referral_event/1)
  end

  defp list_pending_referral_rewards(limit, users) do
    ReferralReward
    |> where([reward], reward.status in ["pending", "approved"])
    |> then(fn query ->
      if is_list(users),
        do: where(query, [reward], reward.recipient_user_id in ^users),
        else: query
    end)
    |> order_by([reward], asc: reward.inserted_at)
    |> limit(^limit)
    |> Repo.all()
    |> Enum.map(&normalize_referral_reward/1)
  end

  defp list_recent_redemptions(limit, users) do
    PromotionRedemption
    |> for_user_memberships(users)
    |> order_by([redemption], desc: redemption.redeemed_at)
    |> limit(^limit)
    |> Repo.all()
    |> Enum.map(&normalize_promotion_redemption/1)
  end

  defp maybe_put_applied_at(params, "applied", nil), do: Map.put(params, :applied_at, utc_now())
  defp maybe_put_applied_at(params, _status, _applied_at), do: params

  defp utc_now, do: DateTime.utc_now() |> DateTime.truncate(:second)

  defp parse_integer(value, _default) when is_integer(value) and value >= 0, do: value

  defp parse_integer(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {integer, ""} when integer >= 0 -> integer
      _ -> default
    end
  end

  defp parse_integer(_value, default), do: default

  defp parse_positive_integer(nil, default), do: {:ok, default}

  defp parse_positive_integer(value, _default) when is_integer(value) and value > 0,
    do: {:ok, value}

  defp parse_positive_integer(value, _default) when is_binary(value) do
    case Integer.parse(value) do
      {integer, ""} when integer > 0 -> {:ok, integer}
      _ -> {:error, :invalid_integer}
    end
  end

  defp parse_positive_integer(_value, _default), do: {:error, :invalid_integer}

  defp parse_non_negative_integer(nil, default), do: {:ok, default}

  defp parse_non_negative_integer(value, _default) when is_integer(value) and value >= 0,
    do: {:ok, value}

  defp parse_non_negative_integer(value, _default) when is_binary(value) do
    case Integer.parse(value) do
      {integer, ""} when integer >= 0 -> {:ok, integer}
      _ -> {:error, :invalid_integer}
    end
  end

  defp parse_non_negative_integer(_value, _default), do: {:error, :invalid_integer}

  defp db_integer(%Decimal{} = value), do: Decimal.to_integer(value)
  defp db_integer(value) when is_integer(value), do: value

  defp normalize_uuid_list(values) when is_list(values) do
    Enum.filter(values, fn value -> match?({:ok, _}, Ecto.UUID.cast(value)) end)
  end

  defp normalize_uuid_list(_values), do: []

  defp dump_uuid_list(values) do
    values
    |> normalize_uuid_list()
    |> Enum.map(&Ecto.UUID.dump!/1)
  end

  defp summary_since(nil), do: Date.add(GymClock.today(), -30)

  defp summary_since(days) when is_integer(days) do
    Date.add(GymClock.today(), -max(days, 1))
  end

  defp summary_since(days) when is_binary(days) do
    case Integer.parse(days) do
      {value, ""} -> summary_since(value)
      _ -> summary_since(nil)
    end
  end

  defp parse_date(%Date{} = date, _default), do: date

  defp parse_date(value, default) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> date
      {:error, _reason} -> default
    end
  end

  defp parse_date(_value, default), do: default

  defp next_invoice_number(line_params) when is_list(line_params) do
    next_invoice_sequence()
    |> InvoiceNumber.format(DateTime.utc_now(), invoice_package_code(line_params))
  end

  defp next_invoice_sequence do
    case Repo.query("SELECT nextval('finance_invoice_number_seq')") do
      {:ok, %{rows: [[sequence]]}} when is_integer(sequence) ->
        sequence

      {:ok, %{rows: [[sequence]]}} ->
        sequence
        |> to_string()
        |> String.to_integer()

      {:error, reason} ->
        raise "could not generate invoice number sequence: #{inspect(reason)}"
    end
  end

  defp invoice_package_code([first_line | _rest]) when is_map(first_line) do
    first_line["package_code_snapshot"] || first_line["package_family_snapshot"] || "manual"
  end

  defp invoice_package_code(_line_params), do: "manual"

  # TD-092: the runtime role does not own the view, so the refresh goes
  # through the allow-listed SECURITY DEFINER helper (ADR-131).
  defp refresh_view(view_name) do
    case Repo.query("SELECT palee_refresh_materialized_view($1)", [view_name]) do
      {:ok, _result} = ok -> ok
      {:error, %Postgrex.Error{postgres: %{message: message}}} -> {:error, message}
      {:error, reason} -> {:error, reason}
    end
  end

  defp normalize_result({:ok, record}, normalizer), do: {:ok, normalizer.(record)}

  defp normalize_result({:error, %Ecto.Changeset{} = changeset}, _normalizer),
    do: {:error, changeset}

  defp tenant_scope(queryable) do
    case RepoContext.current_setting("app.organization_id") do
      organization_id when is_binary(organization_id) and organization_id != "" ->
        from(row in queryable, where: field(row, :organization_id) == ^organization_id)

      _ ->
        from(row in queryable, where: false)
    end
  end

  defp normalize_package(%MembershipPackage{} = package) do
    %{
      id: package.id,
      organization_id: package.organization_id,
      code: package.code,
      name: package.name,
      description: package.description,
      family: package.family,
      package_type: package.package_type,
      billing_period: package.billing_period,
      base_price_cents: package.base_price_cents,
      currency: package.currency,
      tags: package.tags || [],
      params: package.params || %{},
      fields: PackageContract.fields_from_params(package.params || %{}),
      changed_fields:
        PackageContract.changed_fields(
          package.package_type,
          package.billing_period,
          PackageContract.fields_from_params(package.params || %{})
        ),
      active: package.active,
      inserted_at: package.inserted_at,
      updated_at: package.updated_at
    }
  end

  defp normalize_membership(%Membership{} = membership) do
    %{
      id: membership.id,
      organization_id: membership.organization_id,
      user_id: membership.user_id,
      user_type_snapshot: membership.user_type_snapshot,
      status: membership.status,
      signup_source: membership.signup_source,
      starts_on: membership.starts_on,
      expires_on: membership.expires_on,
      notes: membership.notes,
      referred_by_user_id: membership.referred_by_user_id,
      entitlement_status: membership.entitlement_status,
      entitlement_source: membership.entitlement_source,
      entitlement_expires_on: membership.entitlement_expires_on,
      entitlement_updated_at: membership.entitlement_updated_at,
      leaving_on: membership.leaving_on,
      left_at: membership.left_at,
      left_by: membership.left_by,
      leave_reason: membership.leave_reason,
      params: membership.params || %{},
      inserted_at: membership.inserted_at,
      updated_at: membership.updated_at
    }
  end

  defp normalize_subscription(%MembershipPackageSubscription{} = subscription) do
    package =
      MembershipPackage
      |> tenant_scope()
      |> Repo.get(subscription.membership_package_id)

    %{
      id: subscription.id,
      organization_id: subscription.organization_id,
      membership_id: subscription.membership_id,
      membership_package_id: subscription.membership_package_id,
      status: subscription.status,
      starts_on: subscription.starts_on,
      ends_on: subscription.ends_on,
      package_name: package && package.name,
      package_code_snapshot: subscription.package_code_snapshot,
      package_family_snapshot: subscription.package_family_snapshot,
      package_type: PackageContract.type_from_params(subscription.params_snapshot || %{}),
      billing_period_snapshot: subscription.billing_period_snapshot,
      price_cents_snapshot: subscription.price_cents_snapshot,
      params_snapshot: subscription.params_snapshot || %{},
      fields: PackageContract.fields_from_params(subscription.params_snapshot || %{}),
      commitment_ends_on: subscription.commitment_ends_on,
      activated_on: subscription.activated_on,
      base_subscription_id: subscription.base_subscription_id,
      corporate_client_id: subscription.corporate_client_id,
      corporate_enrolled_via: subscription.corporate_enrolled_via,
      referral_reward_applied: subscription.referral_reward_applied,
      auto_renew: MemberRenewal.auto_renew(subscription),
      renewal_changed_at: subscription.renewal_changed_at,
      renewal_changed_by: subscription.renewal_changed_by,
      inserted_at: subscription.inserted_at,
      updated_at: subscription.updated_at
    }
  end

  defp normalize_payment(%MembershipPayment{} = payment) do
    reversed_cents = payment_reversed_cents(payment.id)

    %{
      id: payment.id,
      organization_id: payment.organization_id,
      membership_id: payment.membership_id,
      membership_package_subscription_id: payment.membership_package_subscription_id,
      finance_invoice_id: payment.finance_invoice_id,
      amount_cents: payment.amount_cents,
      reversed_cents: reversed_cents,
      net_amount_cents: max(payment.amount_cents - reversed_cents, 0),
      currency: payment.currency,
      paid_on: payment.paid_on,
      payment_method: payment.payment_method,
      payment_status: payment.payment_status,
      notes: payment.notes,
      params: payment.params || %{},
      inserted_at: payment.inserted_at,
      updated_at: payment.updated_at
    }
  end

  defp normalize_payment_reversal(%FinancePaymentReversal{} = reversal) do
    %{
      id: reversal.id,
      organization_id: reversal.organization_id,
      membership_id: reversal.membership_id,
      user_id: reversal.user_id,
      membership_payment_id: reversal.membership_payment_id,
      finance_invoice_id: reversal.finance_invoice_id,
      reversal_type: reversal.reversal_type,
      amount_cents: reversal.amount_cents,
      currency: reversal.currency,
      occurred_on: reversal.occurred_on,
      occurred_at: reversal.occurred_at,
      reason: reversal.reason,
      created_by_id: reversal.created_by_id,
      idempotency_key: reversal.idempotency_key,
      params: reversal.params || %{},
      inserted_at: reversal.inserted_at,
      updated_at: reversal.updated_at
    }
  end

  defp normalize_promotion_campaign(%PromotionCampaign{} = campaign) do
    %{
      id: campaign.id,
      organization_id: campaign.organization_id,
      name: campaign.name,
      description: campaign.description,
      starts_on: campaign.starts_on,
      ends_on: campaign.ends_on,
      active: campaign.active,
      params: campaign.params || %{},
      location_scope: %{
        all_locations: campaign.all_locations != false,
        location_ids:
          if(campaign.all_locations == false, do: campaign.location_ids || [], else: [])
      },
      inserted_at: campaign.inserted_at,
      updated_at: campaign.updated_at
    }
  end

  defp normalize_promotion_code(%PromotionCode{} = code) do
    %{
      id: code.id,
      organization_id: code.organization_id,
      promotion_campaign_id: code.promotion_campaign_id,
      code: code.code,
      discount_type: code.discount_type,
      discount_value: code.discount_value,
      max_redemptions: code.max_redemptions,
      active: code.active,
      params: code.params || %{},
      inserted_at: code.inserted_at,
      updated_at: code.updated_at
    }
  end

  defp normalize_promotion_redemption(%PromotionRedemption{} = redemption) do
    %{
      id: redemption.id,
      organization_id: redemption.organization_id,
      promotion_campaign_id: redemption.promotion_campaign_id,
      promotion_code_id: redemption.promotion_code_id,
      membership_id: redemption.membership_id,
      membership_payment_id: redemption.membership_payment_id,
      membership_package_subscription_id: redemption.membership_package_subscription_id,
      discount_type_snapshot: redemption.discount_type_snapshot,
      discount_value_snapshot: redemption.discount_value_snapshot,
      redeemed_at: redemption.redeemed_at,
      params: redemption.params || %{}
    }
  end

  defp normalize_referral_program(%ReferralProgram{} = program) do
    %{
      id: program.id,
      organization_id: program.organization_id,
      name: program.name,
      description: program.description,
      active: program.active,
      reward_type: program.reward_type,
      reward_value: program.reward_value,
      reward_note: program.reward_note,
      friend_reward_type: program.friend_reward_type,
      friend_reward_value: program.friend_reward_value,
      friend_reward_note: program.friend_reward_note,
      qualifying_stage: program.qualifying_stage,
      attribution_days: program.attribution_days,
      yearly_cap: program.yearly_cap,
      approval: program.approval,
      params: program.params || %{},
      inserted_at: program.inserted_at,
      updated_at: program.updated_at
    }
  end

  defp normalize_referral_event(%ReferralEvent{} = event) do
    %{
      id: event.id,
      organization_id: event.organization_id,
      referral_program_id: event.referral_program_id,
      referrer_user_id: event.referrer_user_id,
      referred_user_id: event.referred_user_id,
      membership_id: event.membership_id,
      status: event.status,
      signup_source_snapshot: event.signup_source_snapshot,
      notes: event.notes,
      params: event.params || %{},
      inserted_at: event.inserted_at,
      updated_at: event.updated_at
    }
  end

  defp normalize_referral_reward(%ReferralReward{} = reward) do
    %{
      id: reward.id,
      organization_id: reward.organization_id,
      referral_event_id: reward.referral_event_id,
      recipient_user_id: reward.recipient_user_id,
      membership_id: reward.membership_id,
      reward_type: reward.reward_type,
      reward_value: reward.reward_value,
      status: reward.status,
      applied_at: reward.applied_at,
      params: reward.params || %{},
      inserted_at: reward.inserted_at,
      updated_at: reward.updated_at
    }
  end

  defp normalize_credit_ledger_entry(%FinanceCreditLedgerEntry{} = entry) do
    reversed_cents =
      if entry.amount_cents < 0 and entry.entry_type in ["application", "invoice_offset"] do
        credit_entry_reversed_cents(entry.id)
      else
        0
      end

    %{
      id: entry.id,
      organization_id: entry.organization_id,
      membership_id: entry.membership_id,
      user_id: entry.user_id,
      membership_payment_id: entry.membership_payment_id,
      finance_invoice_id: entry.finance_invoice_id,
      finance_invoice_line_id: entry.finance_invoice_line_id,
      referral_reward_id: entry.referral_reward_id,
      promotion_redemption_id: entry.promotion_redemption_id,
      reversed_credit_ledger_entry_id: entry.reversed_credit_ledger_entry_id,
      source_type: entry.source_type,
      entry_type: entry.entry_type,
      amount_cents: entry.amount_cents,
      reversed_cents: reversed_cents,
      remaining_reversible_cents: max(abs(entry.amount_cents || 0) - reversed_cents, 0),
      currency: entry.currency,
      occurred_on: entry.occurred_on,
      occurred_at: entry.occurred_at,
      description: entry.description,
      created_by_id: entry.created_by_id,
      idempotency_key: entry.idempotency_key,
      params: entry.params || %{},
      inserted_at: entry.inserted_at,
      updated_at: entry.updated_at
    }
  end

  defp normalize_invoice_with_balance(%FinanceInvoice{} = invoice) do
    invoice
    |> normalize_invoice()
    |> Map.put(:paid_cents, invoice_paid_cents(invoice.id))
    |> Map.put(:credit_applied_cents, invoice_credit_applied_cents(invoice.id))
    |> Map.put(:balance_due_cents, invoice_balance_due(invoice.id))
    |> Map.put(:lines, list_invoice_lines(invoice.id))
  end

  defp normalize_invoice_with_computed_status(%FinanceInvoice{} = invoice) do
    paid_cents = invoice_paid_cents(invoice.id)
    credit_applied_cents = invoice_credit_applied_cents(invoice.id)

    invoice
    |> normalize_invoice()
    |> Map.put(
      :status,
      InvoiceLifecycle.status(
        invoice.total_cents,
        paid_cents,
        credit_applied_cents,
        invoice.due_date,
        GymClock.today(),
        invoice.status,
        invoice.params
      )
    )
    |> Map.put(:paid_cents, paid_cents)
    |> Map.put(:credit_applied_cents, credit_applied_cents)
    |> Map.put(:balance_due_cents, invoice_balance_due(invoice.id))
    |> Map.put(:lines, list_invoice_lines(invoice.id))
  end

  defp normalize_invoice(%FinanceInvoice{} = invoice) do
    %{
      id: invoice.id,
      organization_id: invoice.organization_id,
      membership_id: invoice.membership_id,
      user_id: invoice.user_id,
      membership_package_subscription_id: invoice.membership_package_subscription_id,
      invoice_number: invoice.invoice_number,
      invoice_type: invoice.invoice_type,
      status: invoice.status,
      issue_date: invoice.issue_date,
      due_date: invoice.due_date,
      service_period_start: invoice.service_period_start,
      service_period_end: invoice.service_period_end,
      subtotal_cents: invoice.subtotal_cents,
      discount_cents: invoice.discount_cents,
      total_cents: invoice.total_cents,
      currency: invoice.currency,
      notes: invoice.notes,
      voided_at: invoice.voided_at,
      deleted_at: invoice.deleted_at,
      deleted_by_id: invoice.deleted_by_id,
      deletion_reason: invoice.deletion_reason,
      params: invoice.params || %{},
      inserted_at: invoice.inserted_at,
      updated_at: invoice.updated_at
    }
  end

  defp cleanup_invoice_record(%FinanceInvoice{} = invoice) do
    document_kind = (invoice.params || %{})["document_kind"]

    %{
      id: invoice.id,
      organization_id: invoice.organization_id,
      record_type: if(document_kind == "receipt", do: "receipt", else: "invoice"),
      code: invoice.invoice_number,
      label: invoice.invoice_number,
      membership_id: invoice.membership_id,
      user_id: invoice.user_id,
      amount_cents: invoice.total_cents,
      currency: invoice.currency,
      status: invoice.status,
      issued_on: invoice.issue_date,
      due_on: invoice.due_date,
      inserted_at: invoice.inserted_at,
      deleted_at: invoice.deleted_at
    }
  end

  defp cleanup_payment_record(%MembershipPayment{} = payment) do
    invoice =
      if payment.finance_invoice_id do
        FinanceInvoice |> tenant_scope() |> Repo.get(payment.finance_invoice_id)
      end

    %{
      id: payment.id,
      organization_id: payment.organization_id,
      record_type: "payment",
      code: payment_code(payment, invoice),
      label: payment_code(payment, invoice),
      membership_id: payment.membership_id,
      user_id: invoice && invoice.user_id,
      finance_invoice_id: payment.finance_invoice_id,
      amount_cents: payment.amount_cents,
      currency: payment.currency,
      status: payment.payment_status,
      paid_on: payment.paid_on,
      inserted_at: payment.inserted_at,
      deleted_at: payment.deleted_at
    }
  end

  defp payment_code(%MembershipPayment{} = payment, %FinanceInvoice{} = invoice),
    do: "#{invoice.invoice_number} / payment #{String.slice(payment.id, 0, 8)}"

  defp payment_code(%MembershipPayment{} = payment, _invoice),
    do: "payment #{String.slice(payment.id, 0, 8)}"

  defp maybe_search_cleanup_invoice(query, value) when value in [nil, ""], do: query

  defp maybe_search_cleanup_invoice(query, value) do
    term = "%#{String.trim(value)}%"

    where(
      query,
      [invoice],
      ilike(invoice.invoice_number, ^term) or fragment("?::text ILIKE ?", invoice.id, ^term)
    )
  end

  defp maybe_search_cleanup_payment(query, value) when value in [nil, ""], do: query

  defp maybe_search_cleanup_payment(query, value) do
    term = "%#{String.trim(value)}%"

    where(
      query,
      [payment],
      fragment("?::text ILIKE ?", payment.id, ^term) or
        fragment("?::text ILIKE ?", payment.finance_invoice_id, ^term)
    )
  end

  defp list_invoice_lines(invoice_id) do
    FinanceInvoiceLine
    |> where([line], line.finance_invoice_id == ^invoice_id)
    |> order_by([line], asc: line.inserted_at)
    |> Repo.all()
    |> Enum.map(&normalize_invoice_line/1)
  end

  defp normalize_invoice_line(%FinanceInvoiceLine{} = line) do
    %{
      id: line.id,
      organization_id: line.organization_id,
      finance_invoice_id: line.finance_invoice_id,
      membership_package_subscription_id: line.membership_package_subscription_id,
      line_type: line.line_type,
      description: line.description,
      quantity: line.quantity,
      unit_amount_cents: line.unit_amount_cents,
      discount_cents: line.discount_cents,
      total_cents: line.total_cents,
      package_code_snapshot: line.package_code_snapshot,
      package_family_snapshot: line.package_family_snapshot,
      params: line.params || %{},
      inserted_at: line.inserted_at,
      updated_at: line.updated_at
    }
  end

  defp normalize_finance_aggregate_row([
         period_start,
         user_type_snapshot,
         package_code,
         package_family,
         membership_count,
         active_membership_count,
         expiring_membership_count,
         paid_revenue_cents,
         pending_revenue_cents,
         promotion_redemption_count,
         promotion_percent_redemption_count,
         promotion_fixed_amount_redemption_count,
         promotion_free_period_redemption_count,
         promotion_manual_redemption_count,
         promotion_realized_discount_cents,
         referral_signup_count,
         pending_referral_reward_count,
         credit_granted_cents,
         credit_applied_cents,
         credit_balance_cents
       ]) do
    %{
      period_start: period_start,
      user_type_snapshot: user_type_snapshot,
      package_code: package_code,
      package_family: package_family,
      membership_count: membership_count,
      active_membership_count: active_membership_count,
      expiring_membership_count: expiring_membership_count,
      paid_revenue_cents: paid_revenue_cents,
      pending_revenue_cents: pending_revenue_cents,
      promotion_redemption_count: promotion_redemption_count,
      promotion_percent_redemption_count: promotion_percent_redemption_count,
      promotion_fixed_amount_redemption_count: promotion_fixed_amount_redemption_count,
      promotion_free_period_redemption_count: promotion_free_period_redemption_count,
      promotion_manual_redemption_count: promotion_manual_redemption_count,
      promotion_realized_discount_cents: promotion_realized_discount_cents,
      referral_signup_count: referral_signup_count,
      pending_referral_reward_count: pending_referral_reward_count,
      credit_granted_cents: credit_granted_cents,
      credit_applied_cents: credit_applied_cents,
      credit_balance_cents: credit_balance_cents
    }
  end

  defp monthly_revenue(rows, first_month) do
    totals =
      Enum.reduce(rows, %{}, fn row, acc ->
        Map.update(
          acc,
          row.period_start,
          %{
            paid_revenue_cents: row.paid_revenue_cents,
            pending_revenue_cents: row.pending_revenue_cents
          },
          fn total ->
            %{
              paid_revenue_cents: total.paid_revenue_cents + row.paid_revenue_cents,
              pending_revenue_cents: total.pending_revenue_cents + row.pending_revenue_cents
            }
          end
        )
      end)

    Enum.map(0..23, fn offset ->
      month = Date.shift(first_month, month: offset)

      Map.merge(
        %{period_start: month},
        Map.get(totals, month, %{paid_revenue_cents: 0, pending_revenue_cents: 0})
      )
    end)
  end

  @contract_keys ["package_type", "billing_period", "fields"]
  @legacy_contract_keys ["params", "family"]

  # ADR-096: v2 writes are normalised by the pure PackageContract. Internal
  # callers that still submit a legacy v1 `params` document keep working as
  # recurring memberships; the public API only accepts the v2 contract.
  defp package_contract_attrs(params, package) do
    base = Map.drop(params, @contract_keys ++ @legacy_contract_keys ++ ["code"])

    cond do
      Enum.any?(["package_type", "fields"], &Map.has_key?(params, &1)) or
          (package && package_v2?(package) && Map.has_key?(params, "billing_period")) ->
        existing =
          package &&
            %{
              package_type: package.package_type,
              billing_period: package.billing_period,
              fields: PackageContract.fields_from_params(package.params || %{})
            }

        with {:ok, contract} <- PackageContract.normalize(params, existing: existing) do
          {:ok,
           Map.merge(base, %{
             "package_type" => contract.package_type,
             "billing_period" => contract.billing_period,
             "params" => PackageContract.to_params(contract)
           })}
        end

      is_nil(package) ->
        {:ok,
         base
         |> Map.put("package_type", "membership")
         |> Map.put("billing_period", params["billing_period"])
         |> Map.put("params", params["params"] || %{})}

      true ->
        {:ok, Map.merge(base, Map.take(params, ["params", "billing_period"]))}
    end
  end

  defp package_terms(params) do
    case EntitlementPlan.parse(params || %{}) do
      {:ok, plan} -> plan.terms
      _ -> %{}
    end
  end

  defp package_v2?(package),
    do: Map.get(package.params || %{}, "entitlement_version") == PackageContract.version()

  defp available_package_code(source) do
    case PackageCode.normalize(source) do
      nil ->
        nil

      base ->
        taken =
          MembershipPackage
          |> tenant_scope()
          |> where([package], package.code == ^base or like(package.code, ^"#{base}_%"))
          |> select([package], package.code)
          |> Repo.all()

        PackageCode.unique(base, taken)
    end
  end

  defp put_subscription_window(params, package) do
    starts_on = parse_date(params["starts_on"], GymClock.today())
    terms = package_terms(package.params)

    ends_on =
      case params["ends_on"] do
        value when value in [nil, ""] ->
          # ADR-097: validity from first use starts on the first reservation.
          if terms[:validity_starts] == "first_use",
            do: nil,
            else: SubscriptionSelection.ends_on(starts_on, package.params || %{})

        value ->
          value
      end

    params
    |> Map.put("starts_on", starts_on)
    |> Map.put("ends_on", ends_on)
    |> Map.put(
      "commitment_ends_on",
      SubscriptionTerms.commitment_ends_on(starts_on, terms[:minimum_commitment_months])
    )
  end

  defp where_allowance_key(query, allowance) when allowance in [:class_visits, "class_visits"] do
    where(
      query,
      [entry],
      entry.allowance_key == "class_visits" or like(entry.allowance_key, "class_visits:%")
    )
  end

  defp where_allowance_key(query, allowance),
    do: where(query, [entry], entry.allowance_key == ^to_string(allowance))

  # ADR-097: ending a membership inside a minimum commitment needs an explicit reason.
  defp guard_commitment!(%Membership{} = membership, %{"status" => status} = params)
       when status in ["cancelled", "inactive"] do
    commitment =
      MembershipPackageSubscription
      |> where([subscription], subscription.membership_id == ^membership.id)
      |> where([subscription], subscription.status == "active")
      |> where([subscription], not is_nil(subscription.commitment_ends_on))
      |> select([subscription], max(subscription.commitment_ends_on))
      |> Repo.one()

    case SubscriptionTerms.cancellation_allowed?(
           commitment,
           GymClock.today(),
           params["commitment_override_reason"]
         ) do
      :ok -> :ok
      {:error, reason} -> Repo.rollback({reason, %{commitment_ends_on: commitment}})
    end
  end

  defp guard_commitment!(_membership, _params), do: :ok

  defp string_key_map(params) when is_map(params) do
    Map.new(params, fn {key, value} -> {to_string(key), value} end)
  end

  defp to_integer_cents(nil), do: 0
  defp to_integer_cents(value) when is_integer(value), do: value
  defp to_integer_cents(%Decimal{} = value), do: Decimal.to_integer(value)
  defp to_integer_cents(value), do: trunc(value)

  # ── Finance Settings ────────────────────────────────────────────────────────

  @impl true
  def get_finance_settings do
    case FinanceSetting |> tenant_scope() |> limit(1) |> Repo.one() do
      nil ->
        %{
          payment_reminder_interval_days: 7,
          subscription_expiry_reminder_days: 5,
          subscription_grace_days: 3,
          entitlement_enforcement_mode: "observe",
          entitlement_timezone: "Europe/Athens",
          document_mode: "invoice",
          package_modules: Palee.Finance.Domain.PackageType.default_modules()
        }

      settings ->
        normalize_finance_settings(settings)
    end
  end

  @impl true
  def update_finance_settings(params) do
    case FinanceSetting |> tenant_scope() |> limit(1) |> Repo.one() do
      nil ->
        organization_id = RepoContext.current_setting("app.organization_id")

        %FinanceSetting{}
        |> FinanceSetting.changeset(Map.put(params, :organization_id, organization_id))
        |> Repo.insert()
        |> normalize_result(&normalize_finance_settings/1)

      %FinanceSetting{} = settings ->
        settings
        |> FinanceSetting.changeset(params)
        |> Repo.update()
        |> normalize_result(&normalize_finance_settings/1)
    end
  end

  defp normalize_finance_settings(%FinanceSetting{} = s) do
    %{
      id: s.id,
      organization_id: s.organization_id,
      payment_reminder_interval_days: s.payment_reminder_interval_days,
      subscription_expiry_reminder_days: s.subscription_expiry_reminder_days,
      subscription_grace_days: s.subscription_grace_days,
      entitlement_enforcement_mode: s.entitlement_enforcement_mode,
      entitlement_timezone: s.entitlement_timezone,
      document_mode: s.document_mode,
      package_modules: s.package_modules,
      inserted_at: s.inserted_at,
      updated_at: s.updated_at
    }
  end

  # ── Outstanding Balance Batch Queries ───────────────────────────────────────

  @impl true
  def outstanding_balance_per_membership([]), do: %{}

  def outstanding_balance_per_membership(membership_ids) when is_list(membership_ids) do
    db_membership_ids = dump_uuid_list(membership_ids)

    sql = """
    SELECT fi.membership_id::text, COALESCE(SUM(
      GREATEST(
        fi.total_cents
        - GREATEST(
            COALESCE((
              SELECT SUM(p.amount_cents)
              FROM membership_payments p
              WHERE p.finance_invoice_id = fi.id
                AND p.payment_status IN ('paid', 'waived')
                AND p.deleted_at IS NULL
            ), 0) - COALESCE((
              SELECT SUM(r.amount_cents)
              FROM finance_payment_reversals r
              WHERE r.finance_invoice_id = fi.id
                AND r.deleted_at IS NULL
            ), 0),
            0
          )
        - GREATEST(
            -COALESCE((
              SELECT SUM(e.amount_cents)
              FROM finance_credit_ledger_entries e
              WHERE e.finance_invoice_id = fi.id
                AND e.entry_type IN ('invoice_offset', 'reversal')
                AND e.deleted_at IS NULL
            ), 0),
            0
          ),
        0
      )
    ), 0) AS outstanding_cents
    FROM finance_invoices fi
    WHERE fi.membership_id = ANY($1::uuid[])
      AND fi.status IN ('issued', 'partially_paid', 'overdue')
      AND fi.deleted_at IS NULL
    GROUP BY fi.membership_id
    """

    case Repo.query(sql, [db_membership_ids]) do
      {:ok, %{rows: rows}} ->
        Map.new(rows, fn [membership_id, cents] ->
          {membership_id, to_integer_cents(cents)}
        end)

      _ ->
        %{}
    end
  end

  @impl true
  def membership_outstanding_balance_cents(membership_id) do
    outstanding_balance_per_membership([membership_id])
    |> Map.get(membership_id, 0)
  end

  @impl true
  def invoice_balance_due_map([]), do: %{}

  def invoice_balance_due_map(invoice_ids) when is_list(invoice_ids) do
    db_invoice_ids = dump_uuid_list(invoice_ids)

    sql = """
    SELECT fi.id::text, GREATEST(
      fi.total_cents
      - GREATEST(
          COALESCE((
            SELECT SUM(p.amount_cents)
            FROM membership_payments p
            WHERE p.finance_invoice_id = fi.id
              AND p.payment_status IN ('paid', 'waived')
              AND p.deleted_at IS NULL
          ), 0) - COALESCE((
            SELECT SUM(r.amount_cents)
            FROM finance_payment_reversals r
            WHERE r.finance_invoice_id = fi.id
              AND r.deleted_at IS NULL
          ), 0),
          0
        )
      - GREATEST(
          -COALESCE((
            SELECT SUM(e.amount_cents)
            FROM finance_credit_ledger_entries e
            WHERE e.finance_invoice_id = fi.id
              AND e.entry_type IN ('invoice_offset', 'reversal')
              AND e.deleted_at IS NULL
          ), 0),
          0
        ),
      0
    ) AS balance_due_cents
    FROM finance_invoices fi
    WHERE fi.id = ANY($1::uuid[])
      AND fi.status NOT IN ('void', 'draft')
      AND fi.deleted_at IS NULL
    """

    case Repo.query(sql, [db_invoice_ids]) do
      {:ok, %{rows: rows}} ->
        Map.new(rows, fn [invoice_id, cents] ->
          {invoice_id, to_integer_cents(cents)}
        end)

      _ ->
        %{}
    end
  end

  # ── Payment Reminder Scheduling ─────────────────────────────────────────────

  @impl true
  def memberships_needing_payment_reminder(interval_days) do
    threshold = DateTime.add(DateTime.utc_now(), -interval_days * 86_400, :second)

    memberships =
      tenant_scope(Membership)
      |> where(
        [m],
        is_nil(m.last_payment_reminder_sent_at) or m.last_payment_reminder_sent_at < ^threshold
      )
      |> Repo.all()

    membership_ids = Enum.map(memberships, & &1.id)
    balances = outstanding_balance_per_membership(membership_ids)

    memberships
    |> Enum.filter(fn m -> Map.get(balances, m.id, 0) > 0 end)
    |> Enum.map(fn m ->
      %{
        membership_id: m.id,
        user_id: m.user_id,
        outstanding_balance_cents: Map.get(balances, m.id, 0)
      }
    end)
  end

  @impl true
  def update_membership_reminder_timestamp(membership_id) do
    tenant_scope(Membership)
    |> where([m], m.id == ^membership_id)
    |> Repo.update_all(set: [last_payment_reminder_sent_at: DateTime.utc_now()])

    :ok
  end

  @impl true
  def subscriptions_needing_expiry_notice(:expiry_reminder, days) when days > 0 do
    today = GymClock.today()

    :expiry_reminder_sent_at
    |> subscription_notices(today, Date.add(today, days))
    # A package with its own reminder days (ADR-097) is reminded by
    # PackageExpiryReminderJob on that day instead, so members get one reminder.
    |> Enum.reject(&((package_terms(&1.params_snapshot)[:expiry_reminder_days] || 0) > 0))
    |> Enum.map(&Map.delete(&1, :params_snapshot))
  end

  def subscriptions_needing_expiry_notice(:grace_notice, days) when days > 0 do
    today = GymClock.today()

    :grace_notice_sent_at
    |> subscription_notices(Date.add(today, -days), Date.add(today, -1))
    |> Enum.map(&Map.delete(&1, :params_snapshot))
  end

  def subscriptions_needing_expiry_notice(_kind, _days), do: []

  # Active subscriptions ending between the two days that were not renewed
  # (no later subscription for the same membership) and not yet notified.
  defp subscription_notices(sent_field, first_day, last_day) do
    from(subscription in MembershipPackageSubscription, as: :subscription)
    |> tenant_scope()
    |> join(:inner, [subscription], membership in Membership,
      on: membership.id == subscription.membership_id
    )
    |> join(:left, [subscription], package in MembershipPackage,
      on: package.id == subscription.membership_package_id
    )
    |> where([subscription], subscription.status == "active")
    |> where([subscription], not is_nil(subscription.ends_on))
    |> where(
      [subscription],
      subscription.ends_on >= ^first_day and subscription.ends_on <= ^last_day
    )
    |> where([subscription], is_nil(field(subscription, ^sent_field)))
    |> where(
      [_subscription, membership],
      membership.status in ["active", "expiring", "trial", "comped"]
    )
    # ADR-220: a member who is leaving chose this end; no reminders about it.
    |> where([_subscription, membership], is_nil(membership.left_at))
    |> where(
      [subscription],
      not exists(
        from(later in MembershipPackageSubscription,
          where:
            later.membership_id == parent_as(:subscription).membership_id and
              later.id != parent_as(:subscription).id and later.status == "active" and
              (is_nil(later.ends_on) or later.ends_on > parent_as(:subscription).ends_on)
        )
      )
    )
    |> select([subscription, membership, package], %{
      subscription_id: subscription.id,
      membership_id: membership.id,
      user_id: membership.user_id,
      ends_on: subscription.ends_on,
      package_name: coalesce(package.name, subscription.package_code_snapshot),
      params_snapshot: subscription.params_snapshot
    })
    |> Repo.all()
  end

  @impl true
  def mark_subscription_notice_sent(subscription_id, kind) do
    field = if kind == :grace_notice, do: :grace_notice_sent_at, else: :expiry_reminder_sent_at

    MembershipPackageSubscription
    |> tenant_scope()
    |> where([subscription], subscription.id == ^subscription_id)
    |> Repo.update_all(set: [{field, utc_now()}])

    :ok
  end

  # ── Renewal choice and leaving the box (ADR-220) ───────────────────────────

  @impl true
  def set_subscription_auto_renew(user_id, subscription_id, auto_renew, by)
      when is_boolean(auto_renew) and by in ["member", "staff"] do
    today = GymClock.today()

    Repo.transaction(fn ->
      with %Membership{} = membership <- locked_membership_for_user(user_id),
           %MembershipPackageSubscription{} = subscription <-
             locked_subscription(membership.id, subscription_id),
           :ok <- renewal_choice_open(subscription, membership, auto_renew, today) do
        if subscription.auto_renew == auto_renew do
          normalize_subscription(subscription)
        else
          now = DateTime.utc_now()
          updated = change_renewal!(subscription, auto_renew, by, now, today)

          unless auto_renew,
            do:
              void_invoices!(
                membership.id,
                &(&1.subscription_ids == [subscription.id] and
                    MemberRenewal.void_after_leaving?(&1, updated.ends_on || today)),
                "Renewal turned off"
              )

          refresh_entitlement_snapshot(membership.id)
          normalize_subscription(updated)
        end
      else
        nil -> Repo.rollback(:not_found)
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  @impl true
  def membership_leave_preview(user_id) do
    today = GymClock.today()

    case membership_for_user(user_id) do
      nil ->
        nil

      %Membership{} = membership ->
        membership.id
        |> running_subscriptions(today)
        |> natural_leaving_day(today)
    end
  end

  @impl true
  def leave_membership(user_id, params) do
    params = string_key_map(params)
    by = params["by"]
    today = GymClock.today()

    Repo.transaction(fn ->
      with %Membership{} = membership <- locked_membership_for_user(user_id),
           :ok <- not_leaving(membership),
           subscriptions = running_subscriptions(membership.id, today),
           {:ok, leaving_on} <- leaving_day(by, params, subscriptions, today) do
        now = DateTime.utc_now()

        not_begun =
          subscriptions
          |> Enum.map(&end_for_leaving!(&1, leaving_on, by, now))
          |> Enum.reject(&is_nil/1)

        # Only what lies after the last day goes: periods that have not begun
        # and packages that never started. Money owed for anything already
        # used stays owed (and reminded) until it is paid.
        voided =
          void_invoices!(
            membership.id,
            &(MemberRenewal.void_after_leaving?(&1, leaving_on) or
                (&1.subscription_ids != [] and
                   Enum.all?(&1.subscription_ids, fn id -> id in not_begun end) and
                   MemberRenewal.unpaid_untouched?(&1))),
            "Member left the box"
          )

        updated =
          membership
          |> Membership.leave_changeset(%{
            leaving_on: leaving_on,
            left_at: now,
            left_by: by,
            leave_reason: blank_to_nil(params["reason"]),
            expires_on: earliest_date(membership.expires_on, leaving_on),
            # Staff marking someone as gone today ends access now.
            status:
              if(by == "staff" and Date.compare(leaving_on, today) != :gt,
                do: "cancelled",
                else: membership.status
              )
          })
          |> Repo.update()
          |> case do
            {:ok, updated} -> updated
            {:error, reason} -> Repo.rollback(reason)
          end

        refresh_entitlement_snapshot(updated.id)

        %{
          membership: normalize_membership(Repo.get!(Membership, updated.id)),
          leaving_on: leaving_on,
          voided_invoice_count: voided,
          outstanding_cents:
            Map.get(outstanding_balance_per_membership([updated.id]), updated.id, 0)
        }
      else
        nil -> Repo.rollback(:not_found)
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  @impl true
  def undo_leave_membership(user_id, by) when by in ["member", "staff"] do
    today = GymClock.today()

    Repo.transaction(fn ->
      with %Membership{} = membership <- locked_membership_for_user(user_id),
           :ok <- undo_open(membership, by, today) do
        now = DateTime.utc_now()

        MembershipPackageSubscription
        |> tenant_scope()
        |> where([subscription], subscription.membership_id == ^membership.id)
        |> where([subscription], subscription.status == "active")
        |> where([subscription], subscription.renewal_changed_at == ^membership.left_at)
        |> lock("FOR UPDATE")
        |> Repo.all()
        |> Enum.each(&resume_after_leave!(&1, by, now))

        rejoin!(membership)
        refresh_entitlement_snapshot(membership.id)
        normalize_membership(Repo.get!(Membership, membership.id))
      else
        nil -> Repo.rollback(:not_found)
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp membership_for_user(user_id) do
    Membership
    |> tenant_scope()
    |> where([membership], membership.user_id == ^user_id)
    |> Repo.one()
  end

  defp locked_membership_for_user(user_id) do
    Membership
    |> tenant_scope()
    |> where([membership], membership.user_id == ^user_id)
    |> lock("FOR UPDATE")
    |> Repo.one()
  end

  defp locked_subscription(membership_id, subscription_id) do
    with {:ok, subscription_id} <- Ecto.UUID.cast(subscription_id) do
      MembershipPackageSubscription
      |> tenant_scope()
      |> where([subscription], subscription.id == ^subscription_id)
      |> where([subscription], subscription.membership_id == ^membership_id)
      |> lock("FOR UPDATE")
      |> Repo.one()
    else
      :error -> nil
    end
  end

  defp renewal_choice_open(subscription, membership, auto_renew, today) do
    cond do
      not MemberRenewal.choice_allowed?(subscription) -> {:error, :renewal_choice_not_allowed}
      not MemberRenewal.running?(subscription, today) -> {:error, :subscription_ended}
      auto_renew and not is_nil(membership.left_at) -> {:error, :member_leaving}
      true -> :ok
    end
  end

  # Turning renewal off gives an open-ended subscription its last day;
  # turning it back on takes that day away again (and the reminders it got).
  defp change_renewal!(subscription, false, by, now, today) do
    open_ended? = is_nil(subscription.ends_on) or subscription.ends_on_from_renewal_stop

    attrs = %{
      auto_renew: false,
      renewal_changed_at: now,
      renewal_changed_by: by,
      ends_on:
        if(open_ended?,
          do: MemberRenewal.last_day(subscription, paid_periods(subscription.id), today),
          else: subscription.ends_on
        ),
      ends_on_from_renewal_stop: open_ended?
    }

    update_renewal!(subscription, attrs)
  end

  defp change_renewal!(subscription, true, by, now, _today) do
    from_stop? = subscription.ends_on_from_renewal_stop

    attrs = %{
      auto_renew: true,
      renewal_changed_at: now,
      renewal_changed_by: by,
      ends_on: if(from_stop?, do: nil, else: subscription.ends_on),
      ends_on_from_renewal_stop: false,
      expiry_reminder_sent_at:
        if(from_stop?, do: nil, else: subscription.expiry_reminder_sent_at),
      grace_notice_sent_at: if(from_stop?, do: nil, else: subscription.grace_notice_sent_at)
    }

    update_renewal!(subscription, attrs)
  end

  defp update_renewal!(subscription, attrs) do
    subscription
    |> MembershipPackageSubscription.renewal_changeset(attrs)
    |> Repo.update()
    |> case do
      {:ok, updated} -> updated
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp running_subscriptions(membership_id, today) do
    MembershipPackageSubscription
    |> tenant_scope()
    |> where([subscription], subscription.membership_id == ^membership_id)
    |> where([subscription], subscription.status == "active")
    |> where([subscription], is_nil(subscription.ends_on) or subscription.ends_on >= ^today)
    |> Repo.all()
  end

  # Periods of the subscription's invoices that were paid, or partly paid
  # (also once such an invoice falls overdue). An invoice belongs to the
  # subscription through its header or any of its lines.
  defp paid_periods(subscription_id) do
    FinanceInvoice
    |> tenant_scope()
    |> where([invoice], invoice.id in subquery(invoice_ids_for_subscription(subscription_id)))
    |> where([invoice], invoice.status not in ["draft", "void"])
    |> where([invoice], is_nil(invoice.deleted_at))
    |> where([invoice], not is_nil(invoice.service_period_end))
    |> Repo.all()
    |> Enum.filter(
      &(&1.status in MemberRenewal.paid_statuses() or invoice_paid_cents(&1.id) > 0 or
          invoice_credit_applied_cents(&1.id) > 0)
    )
    |> Enum.map(&{&1.service_period_start, &1.service_period_end})
  end

  defp invoice_ids_for_subscription(subscription_id) do
    header =
      FinanceInvoice
      |> where([invoice], invoice.membership_package_subscription_id == ^subscription_id)
      |> select([invoice], invoice.id)

    FinanceInvoiceLine
    |> where([line], line.membership_package_subscription_id == ^subscription_id)
    |> select([line], line.finance_invoice_id)
    |> union(^header)
  end

  defp not_leaving(%Membership{left_at: nil}), do: :ok
  defp not_leaving(_membership), do: {:error, :member_leaving}

  defp undo_open(%Membership{left_at: nil}, _by, _today), do: {:error, :not_leaving}
  defp undo_open(_membership, "staff", _today), do: :ok
  defp undo_open(%Membership{left_by: "staff"}, "member", _today), do: {:error, :left_by_staff}
  defp undo_open(membership, "member", today), do: MemberRenewal.undo_allowed(membership, today)

  # Members keep everything they paid for; staff may name the day, today at
  # the earliest (what was already used stays owed either way).
  defp leaving_day("member", _params, subscriptions, today),
    do: {:ok, natural_leaving_day(subscriptions, today)}

  defp leaving_day("staff", params, subscriptions, today) do
    case params["leaving_on"] do
      value when value in [nil, ""] ->
        {:ok, natural_leaving_day(subscriptions, today)}

      value ->
        with %Date{} = leaving_on <- parse_date(value, {:error, :invalid_leaving_on}),
             :ok <- not_in_past(leaving_on, today),
             :ok <-
               MemberRenewal.staff_leaving_allowed(
                 leaving_on,
                 subscriptions |> Enum.map(& &1.commitment_ends_on) |> latest_date(),
                 params["commitment_override_reason"]
               ) do
          {:ok, leaving_on}
        end
    end
  end

  defp leaving_day(_by, _params, _subscriptions, _today), do: {:error, :invalid_leave_actor}

  defp not_in_past(leaving_on, today) do
    if Date.compare(leaving_on, today) == :lt, do: {:error, :invalid_leaving_on}, else: :ok
  end

  # Packages that have not begun yet do not keep the member: they are
  # cancelled with the leave.
  defp natural_leaving_day(subscriptions, today) do
    subscriptions
    |> Enum.filter(&(is_nil(&1.starts_on) or Date.compare(&1.starts_on, today) != :gt))
    |> Enum.map(&MemberRenewal.last_day(&1, paid_periods(&1.id), today))
    |> MemberRenewal.leaving_on(today)
  end

  # Every running subscription stops renewing and ends by the last day; one
  # that would only start after it is cancelled (its id is returned).
  defp end_for_leaving!(subscription, leaving_on, by, now) do
    if subscription.starts_on && Date.compare(subscription.starts_on, leaving_on) == :gt do
      subscription
      |> MembershipPackageSubscription.changeset(%{"status" => "cancelled"})
      |> Repo.update()
      |> case do
        {:ok, cancelled} -> cancelled.id
        {:error, reason} -> Repo.rollback(reason)
      end
    else
      stop_for_leaving!(subscription, leaving_on, by, now)
      nil
    end
  end

  # Renewal the member had already turned off keeps who turned it off and
  # when, so undoing the leave leaves it off; only its last day may move in.
  defp stop_for_leaving!(%{auto_renew: false} = subscription, leaving_on, _by, _now) do
    ends_on = earliest_date(subscription.ends_on, leaving_on)

    if ends_on != subscription.ends_on,
      do:
        update_renewal!(subscription, %{
          auto_renew: false,
          renewal_changed_at: subscription.renewal_changed_at,
          renewal_changed_by: subscription.renewal_changed_by,
          ends_on: ends_on
        })
  end

  defp stop_for_leaving!(subscription, leaving_on, by, now) do
    open_ended? = is_nil(subscription.ends_on) or subscription.ends_on_from_renewal_stop

    update_renewal!(subscription, %{
      auto_renew: false,
      renewal_changed_at: now,
      renewal_changed_by: by,
      ends_on: earliest_date(subscription.ends_on, leaving_on),
      ends_on_from_renewal_stop: open_ended?
    })
  end

  defp resume_after_leave!(subscription, by, now) do
    attrs = %{
      auto_renew: MemberRenewal.choice_allowed?(subscription),
      renewal_changed_at: now,
      renewal_changed_by: by,
      ends_on: if(subscription.ends_on_from_renewal_stop, do: nil, else: subscription.ends_on),
      ends_on_from_renewal_stop: false,
      expiry_reminder_sent_at: nil,
      grace_notice_sent_at: nil
    }

    update_renewal!(subscription, attrs)
  end

  # Coming back (staff undo the leave or assign a new package) clears it;
  # a membership staff had cancelled for the leave is active again.
  defp rejoin!(%Membership{left_at: nil}), do: :ok

  defp rejoin!(%Membership{} = membership) do
    status =
      if membership.status == "cancelled" and membership.left_by == "staff",
        do: "active",
        else: membership.status

    membership
    |> Membership.leave_changeset(%{
      leaving_on: nil,
      left_at: nil,
      left_by: nil,
      leave_reason: nil,
      expires_on:
        if(membership.expires_on == membership.leaving_on, do: nil, else: membership.expires_on),
      status: status
    })
    |> Repo.update()
    |> case do
      {:ok, _membership} -> :ok
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  # The subscriptions an invoice is for: its header's and its lines'.
  defp invoice_subscription_ids(invoice) do
    FinanceInvoiceLine
    |> where([line], line.finance_invoice_id == ^invoice.id)
    |> where([line], not is_nil(line.membership_package_subscription_id))
    |> select([line], line.membership_package_subscription_id)
    |> Repo.all()
    |> then(
      &Enum.uniq(
        Enum.reject([invoice.membership_package_subscription_id | &1], fn id -> is_nil(id) end)
      )
    )
  end

  # Voids the membership's open invoices `void?` picks (it gets each invoice
  # with what was paid and credited on it and the subscriptions it is for);
  # returns how many.
  defp void_invoices!(membership_id, void?, note) do
    FinanceInvoice
    |> tenant_scope()
    |> where([invoice], invoice.membership_id == ^membership_id)
    |> where([invoice], invoice.status in ["draft", "issued", "overdue"])
    |> where([invoice], is_nil(invoice.deleted_at))
    |> lock("FOR UPDATE")
    |> Repo.all()
    |> Enum.map(fn invoice ->
      invoice
      |> Map.from_struct()
      |> Map.merge(%{
        paid_cents: invoice_paid_cents(invoice.id),
        credit_applied_cents: invoice_credit_applied_cents(invoice.id),
        subscription_ids: invoice_subscription_ids(invoice),
        invoice: invoice
      })
    end)
    |> Enum.filter(void?)
    |> Enum.map(fn %{invoice: invoice} ->
      invoice
      |> FinanceInvoice.changeset(%{
        status: "void",
        voided_at: utc_now(),
        notes: Enum.join(Enum.reject([invoice.notes, note], &(&1 in [nil, ""])), "\n")
      })
      |> Repo.update()
      |> case do
        {:ok, voided} -> release_referral_discounts(voided.id)
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
    |> length()
  end

  defp earliest_date(nil, date), do: date
  defp earliest_date(date, nil), do: date
  defp earliest_date(left, right), do: Enum.min([left, right], Date)

  defp latest_date(dates) do
    case Enum.reject(dates, &is_nil/1) do
      [] -> nil
      dates -> Enum.max(dates, Date)
    end
  end

  defp blank_to_nil(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp blank_to_nil(_value), do: nil

  @impl true
  def refresh_entitlement_snapshots do
    Membership
    |> tenant_scope()
    |> Repo.all()
    |> Enum.flat_map(fn membership ->
      refresh_entitlement_snapshot(membership.id)
      updated = Repo.get(Membership, membership.id)

      # Lost access with this refresh (e.g. the grace slack is over).
      if (membership.entitlement_status in ["active", "grace"] and updated) &&
           updated.entitlement_status in ["inactive", "blocked"] do
        [
          %{
            membership_id: updated.id,
            user_id: updated.user_id,
            status: updated.entitlement_status,
            source: updated.entitlement_source
          }
        ]
      else
        []
      end
    end)
  end

  @impl true
  def total_outstanding_balance_cents do
    sql = """
    SELECT COALESCE(SUM(GREATEST(
      fi.total_cents
      - GREATEST(
          COALESCE((
            SELECT SUM(p.amount_cents)
            FROM membership_payments p
            WHERE p.finance_invoice_id = fi.id
              AND p.payment_status IN ('paid', 'waived')
              AND p.deleted_at IS NULL
          ), 0) - COALESCE((
            SELECT SUM(r.amount_cents)
            FROM finance_payment_reversals r
            WHERE r.finance_invoice_id = fi.id
              AND r.deleted_at IS NULL
          ), 0),
          0
        )
      - GREATEST(
          -COALESCE((
            SELECT SUM(e.amount_cents)
            FROM finance_credit_ledger_entries e
            WHERE e.finance_invoice_id = fi.id
              AND e.entry_type IN ('invoice_offset', 'reversal')
              AND e.deleted_at IS NULL
          ), 0),
          0
        ),
      0
    )), 0)
    FROM finance_invoices fi
    WHERE fi.status NOT IN ('void', 'draft')
      AND fi.deleted_at IS NULL
    """

    case Repo.query(sql, []) do
      {:ok, %{rows: [[total]]}} -> to_integer_cents(total)
      _ -> 0
    end
  end

  @impl true
  def count_pending_referral_approvals do
    ReferralReward
    |> where([r], r.status == "pending")
    |> select([r], count(r.id))
    |> Repo.one()
    |> Kernel.||(0)
  end
end
