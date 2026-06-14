defmodule MilosTraining.Infrastructure.Finance.EctoFinanceStore do
  @behaviour MilosTraining.Finance.Ports.FinanceStore

  import Ecto.Query

  alias MilosTraining.Finance.{
    FinanceCreditLedgerEntry,
    FinanceInvoice,
    FinanceInvoiceLine,
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

  alias MilosTraining.Finance.Domain.{
    CreditLedger,
    InvoiceLifecycle,
    MembershipLifecycle,
    MembershipLinks,
    PromotionRedemptionPolicy,
    ReferralLifecycle,
    ReferralPolicy,
    ReferralRewardFulfillment
  }

  alias MilosTraining.Repo

  @impl true
  def create_package(params) do
    %MembershipPackage{}
    |> MembershipPackage.changeset(params)
    |> Repo.insert()
    |> normalize_result(&normalize_package/1)
  end

  @impl true
  def update_package(id, params) do
    case Repo.get(MembershipPackage, id) do
      nil ->
        {:error, :not_found}

      %MembershipPackage{} = package ->
        package
        |> MembershipPackage.changeset(params)
        |> Repo.update()
        |> normalize_result(&normalize_package/1)
    end
  end

  @impl true
  def list_packages do
    MembershipPackage
    |> order_by([package], asc: package.code)
    |> Repo.all()
    |> Enum.map(&normalize_package/1)
  end

  @impl true
  def get_package(id) do
    case Repo.get(MembershipPackage, id) do
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
      membership =
        case Repo.get_by(Membership, user_id: user_id) do
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
      Membership |> Repo.get!(membership.id) |> normalize_membership()
    end)
  end

  @impl true
  def get_member_profile(user_id) do
    case Repo.get_by(Membership, user_id: user_id) do
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

  @impl true
  def search_member_summaries(params) do
    params = string_key_map(params || %{})
    user_ids = normalize_uuid_list(params["user_ids"])
    limit = parse_integer(params["limit"], 50) |> min(100_000) |> max(1)

    from(membership in Membership, as: :membership)
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
           %MembershipPackage{} = package <- Repo.get(MembershipPackage, package_id),
           :ok <- validate_package_active(package) do
        params =
          params
          |> string_key_map()
          |> Map.merge(%{
            "membership_id" => membership.id,
            "membership_package_id" => package.id,
            "package_code_snapshot" => package.code,
            "package_family_snapshot" => package.family,
            "billing_period_snapshot" => package.billing_period,
            "price_cents_snapshot" => package.base_price_cents,
            "params_snapshot" => package.params || %{}
          })

        subscription =
          %MembershipPackageSubscription{}
          |> MembershipPackageSubscription.changeset(params)
          |> Repo.insert()
          |> case do
            {:ok, subscription} -> subscription
            {:error, reason} -> Repo.rollback(reason)
          end

        refresh_entitlement_snapshot(membership.id)
        normalize_subscription(subscription)
      else
        nil -> Repo.rollback(:not_found)
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  @impl true
  def record_payment(membership_id, params) do
    params =
      params
      |> string_key_map()
      |> Map.put("membership_id", membership_id)
      |> Map.put_new("paid_on", Date.utc_today())

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
  def create_manual_credit(membership_id, params) do
    params = string_key_map(params)

    Repo.transaction(fn ->
      with %Membership{} = membership <- locked_membership(membership_id),
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
               "occurred_on" => Date.utc_today(),
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
               "occurred_on" => Date.utc_today(),
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
           :ok <-
             MembershipLinks.validate_optional_link(
               :membership_payment_id,
               membership.id,
               payment.membership_id
             ),
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
               "occurred_on" => Date.utc_today(),
               "occurred_at" => utc_now(),
               "reason" => params["reason"] || params["description"] || params["notes"],
               "created_by_id" => params["created_by_id"],
               "idempotency_key" =>
                 scoped_finance_key("payment_reversal:#{payment.id}", membership.id, params),
               "params" => reversal_params(params, payment.id)
             }) do
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
               "occurred_on" => Date.utc_today(),
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
  def get_invoice(invoice_id) do
    case Repo.get(FinanceInvoice, invoice_id) do
      nil -> {:error, :not_found}
      invoice -> {:ok, invoice}
    end
  end

  @impl true
  def update_invoice_params(invoice_id, params) do
    case Repo.get(FinanceInvoice, invoice_id) do
      nil ->
        {:error, :not_found}

      invoice ->
        invoice
        |> FinanceInvoice.changeset(%{params: params})
        |> Repo.update()
        |> normalize_result(&normalize_invoice/1)
    end
  end

  @impl true
  def create_invoice(membership_id, params) do
    params = string_key_map(params)

    with %Membership{} = membership <- Repo.get(Membership, membership_id),
         :ok <- validate_invoice_subscription_link(membership.id, params),
         {:ok, line_params} <- invoice_line_params(params),
         :ok <- validate_invoice_line_subscription_links(membership.id, line_params),
         totals <- InvoiceLifecycle.invoice_totals(line_params) do
      Repo.transaction(fn ->
        invoice =
          %FinanceInvoice{}
          |> FinanceInvoice.changeset(
            params
            |> Map.put("membership_id", membership.id)
            |> Map.put("user_id", membership.user_id)
            |> Map.put_new("invoice_number", next_invoice_number())
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

    with %Membership{} = membership <- Repo.get(Membership, membership_id),
         %MembershipPackageSubscription{} = subscription <-
           renewal_subscription(membership.id, params["membership_package_subscription_id"]) do
      period_start = parse_date(params["service_period_start"], Date.utc_today())

      with {:ok, {period_start, period_end}} <-
             InvoiceLifecycle.renewal_period(
               subscription.billing_period_snapshot,
               period_start,
               parse_date(params["service_period_end"], nil)
             ) do
        if renewal_invoice_exists?(membership.id, subscription.id, period_start, period_end) do
          {:error, :duplicate_renewal_invoice}
        else
          case create_invoice(membership.id, %{
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
                     "discount_cents" => 0,
                     "package_code_snapshot" => subscription.package_code_snapshot,
                     "package_family_snapshot" => subscription.package_family_snapshot
                   }
                 ]
               }) do
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
            issue_date: params["issue_date"] || invoice.issue_date || Date.utc_today(),
            due_date: params["due_date"] || invoice.due_date || Date.utc_today()
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
               "occurred_on" => Date.utc_today(),
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
    case Repo.get_by(Membership, user_id: user_id) do
      nil -> nil
      %Membership{} = membership -> entitlement_for_membership(membership)
    end
  end

  @impl true
  def list_expiring_memberships(days) do
    today = Date.utc_today()
    cutoff = Date.add(Date.utc_today(), parse_integer(days, 30))

    Membership
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

    %{
      expiring_memberships: Enum.take(list_expiring_memberships(expiring_within_days), limit),
      pending_payments: list_pending_payments(limit),
      overdue_invoices: list_overdue_invoices(limit),
      pending_referral_events: list_pending_referral_events(limit),
      pending_referral_rewards: list_pending_referral_rewards(limit),
      promotion_redemptions: list_recent_redemptions(limit)
    }
  end

  def financial_summary, do: financial_summary(%{})

  @impl true
  def financial_summary(params) do
    params = string_key_map(params || %{})
    since = summary_since(params["days"])
    renewal_metrics = renewal_invoice_metrics()
    first_month = Date.utc_today() |> Date.beginning_of_month() |> Date.shift(month: -23)

    {aggregate_status, aggregate_error, aggregate_rows} =
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
             WHERE period_start >= $1
             ORDER BY period_start DESC, package_code ASC
             """,
             [first_month]
           ) do
        {:ok, %{rows: rows}} ->
          {"available", nil, Enum.map(rows, &normalize_finance_aggregate_row/1)}

        {:error, reason} ->
          {"unavailable", inspect(reason), []}
      end

    %{
      aggregates: aggregate_rows,
      monthly_revenue: monthly_revenue(aggregate_rows, first_month),
      aggregate_status: aggregate_status,
      aggregate_error: aggregate_error,
      period: %{since: since, days: parse_integer(params["days"], 30)},
      totals: %{
        active_memberships: active_membership_count(),
        expiring_memberships: length(list_expiring_memberships(30)),
        paid_revenue_cents: total_paid_revenue_cents(since),
        credit_balance_cents: total_credit_balance_cents(),
        outstanding_invoice_balance_cents: total_outstanding_invoice_balance_cents(),
        overdue_invoice_balance_cents: total_overdue_invoice_balance_cents(),
        invoice_credit_offset_cents: total_invoice_credit_offset_cents(),
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
    case Repo.get(PromotionCampaign, campaign_id) do
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
    %ReferralProgram{}
    |> ReferralProgram.changeset(params)
    |> Repo.insert()
    |> normalize_result(&normalize_referral_program/1)
  end

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
    case Repo.get(ReferralEvent, id) do
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
    |> order_by([event], desc: event.inserted_at)
    |> Repo.all()
    |> Enum.map(&normalize_referral_event/1)
  end

  @impl true
  def create_referral_reward(referral_event_id, params) do
    case Repo.get(ReferralEvent, referral_event_id) do
      nil ->
        {:error, :not_found}

      %ReferralEvent{} = event ->
        with :ok <-
               ReferralPolicy.validate_reward_creation(
                 event.status,
                 referral_reward_exists?(event.id)
               ),
             {:ok, program} <- active_referral_program(event.referral_program_id) do
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
  def list_referral_rewards do
    ReferralReward
    |> order_by([reward], desc: reward.inserted_at)
    |> Repo.all()
    |> Enum.map(&normalize_referral_reward/1)
  end

  @impl true
  def update_referral_reward_status(id, status) do
    case Repo.get(ReferralReward, id) do
      nil ->
        {:error, :not_found}

      %ReferralReward{} = reward ->
        with :ok <- ReferralLifecycle.validate_transition(reward.status, status),
             {:ok, event} <- get_reward_event(reward),
             :ok <- validate_reward_event_status(event, status),
             {:ok, updated_reward} <- update_reward_and_event(reward, event, status) do
          {:ok, normalize_referral_reward(updated_reward)}
        end
    end
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
        maybe_create_referral_reward_credit_grant(reward, amount_cents)

      {:ok, :lifecycle_only} ->
        reward

      {:error, reason} ->
        Repo.rollback(reason)
    end
  end

  defp fulfill_referral_reward(%ReferralReward{} = reward, _status), do: reward

  defp maybe_create_referral_reward_credit_grant(%ReferralReward{} = reward, amount_cents) do
    idempotency_key = "referral_reward:#{reward.id}"

    if Repo.get_by(FinanceCreditLedgerEntry, idempotency_key: idempotency_key) do
      reward
    else
      with %Membership{} = membership <-
             Repo.get_by(Membership, user_id: reward.recipient_user_id),
           {:ok, _entry} <-
             create_credit_entry(%{
               "membership_id" => membership.id,
               "user_id" => membership.user_id,
               "referral_reward_id" => reward.id,
               "source_type" => "referral_reward",
               "entry_type" => "grant",
               "amount_cents" => amount_cents,
               "currency" => "EUR",
               "occurred_on" => Date.utc_today(),
               "occurred_at" => reward.applied_at || utc_now(),
               "description" => "Referral reward credit",
               "idempotency_key" => idempotency_key,
               "params" => %{
                 referral_event_id: reward.referral_event_id,
                 reward_type: reward.reward_type
               }
             }) do
        reward
      else
        nil -> Repo.rollback(:recipient_membership_not_found)
        {:error, reason} -> Repo.rollback(reason)
      end
    end
  end

  defp locked_membership(membership_id) do
    Membership
    |> where([membership], membership.id == ^membership_id)
    |> lock("FOR UPDATE")
    |> Repo.one()
  end

  defp locked_payment(payment_id) do
    MembershipPayment
    |> where([payment], payment.id == ^payment_id)
    |> lock("FOR UPDATE")
    |> Repo.one()
  end

  defp locked_credit_ledger_entry(entry_id) do
    FinanceCreditLedgerEntry
    |> where([entry], entry.id == ^entry_id)
    |> lock("FOR UPDATE")
    |> Repo.one()
  end

  defp locked_invoice(invoice_id) do
    FinanceInvoice
    |> where([invoice], invoice.id == ^invoice_id)
    |> lock("FOR UPDATE")
    |> Repo.one()
  end

  defp scoped_idempotency_key(action, membership_id, params) do
    request_id = params["request_id"] || Ecto.UUID.generate()
    "finance_credit:#{action}:#{membership_id}:#{request_id}"
  end

  defp scoped_finance_key(action, membership_id, params) do
    request_id = params["request_id"] || Ecto.UUID.generate()
    "finance:#{action}:#{membership_id}:#{request_id}"
  end

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
    |> order_by([entry], desc: entry.occurred_at, desc: entry.inserted_at)
    |> Repo.all()
    |> Enum.map(&normalize_credit_ledger_entry/1)
  end

  defp list_payment_reversals(membership_id) do
    FinancePaymentReversal
    |> where([reversal], reversal.membership_id == ^membership_id)
    |> order_by([reversal], desc: reversal.occurred_at, desc: reversal.inserted_at)
    |> Repo.all()
    |> Enum.map(&normalize_payment_reversal/1)
  end

  defp list_invoices(membership_id) do
    FinanceInvoice
    |> where([invoice], invoice.membership_id == ^membership_id)
    |> order_by([invoice], desc: invoice.inserted_at)
    |> Repo.all()
    |> Enum.map(&normalize_invoice_with_balance/1)
  end

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
    today = Date.utc_today()

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
    case Repo.get(MembershipPackageSubscription, subscription_id) do
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
                 Date.utc_today()
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
        where: invoice.status != "void"
      )
    )
  end

  defp invoice_paid_cents(invoice_id) do
    paid_cents =
      MembershipPayment
      |> where([payment], payment.finance_invoice_id == ^invoice_id)
      |> where([payment], payment.payment_status in ["paid", "waived"])
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
    |> Repo.aggregate(:sum, :amount_cents)
    |> case do
      nil -> 0
      value -> value
    end
  end

  defp invoice_payment_reversed_cents(invoice_id) do
    FinancePaymentReversal
    |> where([reversal], reversal.finance_invoice_id == ^invoice_id)
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
    |> Repo.aggregate(:sum, :amount_cents)
    |> case do
      nil -> 0
      value -> value
    end
  end

  defp invoice_balance_due(invoice_id) do
    case Repo.get(FinanceInvoice, invoice_id) do
      nil ->
        0

      %FinanceInvoice{status: "void"} ->
        0

      %FinanceInvoice{} = invoice ->
        max(
          invoice.total_cents - invoice_paid_cents(invoice.id) -
            invoice_credit_applied_cents(invoice.id),
          0
        )
    end
  end

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
              Date.utc_today(),
              invoice.status
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
      |> Repo.all()

    today = Date.utc_today()

    open_invoice_count =
      Enum.count(blocking_invoices, fn invoice -> invoice_balance_due(invoice.id) > 0 end)

    overdue_invoice_count =
      Enum.count(blocking_invoices, fn invoice ->
        invoice_balance_due(invoice.id) > 0 and invoice.due_date != nil and
          Date.compare(today, invoice.due_date) == :gt
      end)

    active_subscription? =
      MembershipPackageSubscription
      |> where([subscription], subscription.membership_id == ^membership.id)
      |> where(
        [subscription],
        subscription.status in ^InvoiceLifecycle.active_subscription_statuses()
      )
      |> where([subscription], is_nil(subscription.starts_on) or subscription.starts_on <= ^today)
      |> where([subscription], is_nil(subscription.ends_on) or subscription.ends_on >= ^today)
      |> Repo.exists?()

    derived =
      InvoiceLifecycle.entitlement(%{
        membership_status: membership.status,
        membership_expires_on: membership.expires_on,
        active_subscription?: active_subscription?,
        open_invoice_count: open_invoice_count,
        overdue_invoice_count: overdue_invoice_count,
        today: Date.utc_today()
      })

    %{
      status: derived.status,
      source: derived.source,
      expires_on: derived.expires_on,
      open_invoice_count: open_invoice_count,
      overdue_invoice_count: overdue_invoice_count,
      credit_balance_cents: credit_balance(membership.id),
      updated_at: membership.entitlement_updated_at
    }
  end

  defp refresh_entitlement_snapshot(nil), do: :ok

  defp refresh_entitlement_snapshot(membership_id) do
    case Repo.get(Membership, membership_id) do
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
      |> Repo.aggregate(:sum, :amount_cents)
      |> case do
        nil -> 0
        value -> abs(value)
      end

    max(payment.amount_cents - applied_cents, 0)
  end

  defp get_reward_event(%ReferralReward{} = reward) do
    case Repo.get(ReferralEvent, reward.referral_event_id) do
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

    Map.new(memberships, fn membership ->
      subscriptions = Map.get(subscriptions_by_membership_id, membership.id, [])
      last_payment = Map.get(last_payments_by_membership_id, membership.id)

      {membership.user_id,
       %{
         membership: normalize_membership(membership),
         package_subscriptions: subscriptions,
         active_package_subscription:
           Enum.find(
             subscriptions,
             &(&1.status in InvoiceLifecycle.active_subscription_statuses())
           ),
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

  defp build_redemption_params(membership, params) do
    case find_promotion_code(params) do
      {:ok, %PromotionCode{} = code} ->
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

      {:error, reason} ->
        {:error, reason}

      :not_requested ->
        if is_binary(params["promotion_campaign_id"]) do
          with %PromotionCampaign{} = campaign <-
                 Repo.get(PromotionCampaign, params["promotion_campaign_id"]),
               :ok <- validate_campaign_active(campaign),
               :ok <- validate_campaign_window(campaign, Date.utc_today()),
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
    case Repo.get(MembershipPackageSubscription, subscription_id) do
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
    case Repo.get(FinanceInvoice, invoice_id) do
      nil ->
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
    case Repo.get(Membership, membership_id) do
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
        params["expires_on"]
      )
    )
  end

  defp active_membership_count do
    today = Date.utc_today()

    Membership
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
           Repo.get(PromotionCampaign, code.promotion_campaign_id),
         :ok <- validate_campaign_active(campaign),
         :ok <- validate_campaign_window(campaign, Date.utc_today()),
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

  defp active_referral_program(nil), do: {:error, :referral_program_required}
  defp active_referral_program(""), do: {:error, :referral_program_required}

  defp active_referral_program(program_id) do
    case Repo.get(ReferralProgram, program_id) do
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

  defp total_paid_revenue_cents(since) do
    payment_reversals =
      from(reversal in FinancePaymentReversal,
        group_by: reversal.membership_payment_id,
        select: %{
          membership_payment_id: reversal.membership_payment_id,
          reversed_cents: sum(reversal.amount_cents)
        }
      )

    MembershipPayment
    |> where([payment], payment.payment_status == "paid")
    |> where([payment], payment.paid_on >= ^since)
    |> join(:left, [payment], reversal in subquery(payment_reversals),
      on: reversal.membership_payment_id == payment.id
    )
    |> select(
      [payment, reversal],
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

  defp total_credit_balance_cents do
    FinanceCreditLedgerEntry
    |> Repo.aggregate(:sum, :amount_cents)
    |> case do
      nil -> 0
      value -> value
    end
  end

  defp total_invoice_credit_offset_cents do
    FinanceCreditLedgerEntry
    |> where([entry], not is_nil(entry.finance_invoice_id))
    |> where([entry], entry.source_type in ["invoice_offset", "reversal"])
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

  defp renewal_invoice_metrics do
    issued_count =
      FinanceInvoice
      |> where([invoice], invoice.invoice_type == "renewal")
      |> where([invoice], invoice.status in ["issued", "partially_paid", "paid", "overdue"])
      |> Repo.aggregate(:count)

    paid_count =
      FinanceInvoice
      |> where([invoice], invoice.invoice_type == "renewal")
      |> where([invoice], invoice.status == "paid")
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

  defp total_outstanding_invoice_balance_cents do
    FinanceInvoice
    |> where([invoice], invoice.status in ["issued", "partially_paid", "overdue"])
    |> Repo.all()
    |> Enum.reduce(0, fn invoice, acc -> acc + invoice_balance_due(invoice.id) end)
  end

  defp total_overdue_invoice_balance_cents do
    FinanceInvoice
    |> where([invoice], invoice.status in ["issued", "partially_paid", "overdue"])
    |> where([invoice], not is_nil(invoice.due_date) and invoice.due_date < ^Date.utc_today())
    |> Repo.all()
    |> Enum.reduce(0, fn invoice, acc -> acc + invoice_balance_due(invoice.id) end)
  end

  defp list_pending_payments(limit) do
    MembershipPayment
    |> where([payment], payment.payment_status in ["pending", "failed"])
    |> order_by([payment], desc: payment.paid_on, desc: payment.inserted_at)
    |> limit(^limit)
    |> Repo.all()
    |> Enum.map(&normalize_payment/1)
  end

  defp list_overdue_invoices(limit) do
    FinanceInvoice
    |> where([invoice], invoice.status in ["issued", "partially_paid", "overdue"])
    |> where([invoice], not is_nil(invoice.due_date) and invoice.due_date < ^Date.utc_today())
    |> order_by([invoice], asc: invoice.due_date)
    |> limit(^limit)
    |> Repo.all()
    |> Enum.map(&normalize_invoice_with_computed_status/1)
    |> Enum.filter(&(&1.balance_due_cents > 0))
  end

  defp list_pending_referral_events(limit) do
    ReferralEvent
    |> where([event], event.status in ["pending", "approved"])
    |> order_by([event], asc: event.inserted_at)
    |> limit(^limit)
    |> Repo.all()
    |> Enum.map(&normalize_referral_event/1)
  end

  defp list_pending_referral_rewards(limit) do
    ReferralReward
    |> where([reward], reward.status in ["pending", "approved"])
    |> order_by([reward], asc: reward.inserted_at)
    |> limit(^limit)
    |> Repo.all()
    |> Enum.map(&normalize_referral_reward/1)
  end

  defp list_recent_redemptions(limit) do
    PromotionRedemption
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

  defp summary_since(nil), do: Date.add(Date.utc_today(), -30)

  defp summary_since(days) when is_integer(days) do
    Date.add(Date.utc_today(), -max(days, 1))
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

  defp next_invoice_number do
    "INV-" <> (Ecto.UUID.generate() |> String.slice(0, 8) |> String.upcase())
  end

  defp refresh_view(view_name) do
    case Repo.query("REFRESH MATERIALIZED VIEW CONCURRENTLY #{view_name}") do
      {:ok, _result} = ok ->
        ok

      {:error, %Postgrex.Error{postgres: %{message: message}}} when is_binary(message) ->
        if String.contains?(message, "cannot run inside a transaction block") do
          Repo.query("REFRESH MATERIALIZED VIEW #{view_name}")
        else
          {:error, message}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp normalize_result({:ok, record}, normalizer), do: {:ok, normalizer.(record)}

  defp normalize_result({:error, %Ecto.Changeset{} = changeset}, _normalizer),
    do: {:error, changeset}

  defp normalize_package(%MembershipPackage{} = package) do
    %{
      id: package.id,
      code: package.code,
      name: package.name,
      description: package.description,
      family: package.family,
      billing_period: package.billing_period,
      base_price_cents: package.base_price_cents,
      currency: package.currency,
      tags: package.tags || [],
      params: package.params || %{},
      active: package.active,
      inserted_at: package.inserted_at,
      updated_at: package.updated_at
    }
  end

  defp normalize_membership(%Membership{} = membership) do
    %{
      id: membership.id,
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
      params: membership.params || %{},
      inserted_at: membership.inserted_at,
      updated_at: membership.updated_at
    }
  end

  defp normalize_subscription(%MembershipPackageSubscription{} = subscription) do
    %{
      id: subscription.id,
      membership_id: subscription.membership_id,
      membership_package_id: subscription.membership_package_id,
      status: subscription.status,
      starts_on: subscription.starts_on,
      ends_on: subscription.ends_on,
      package_code_snapshot: subscription.package_code_snapshot,
      package_family_snapshot: subscription.package_family_snapshot,
      billing_period_snapshot: subscription.billing_period_snapshot,
      price_cents_snapshot: subscription.price_cents_snapshot,
      params_snapshot: subscription.params_snapshot || %{},
      referral_reward_applied: subscription.referral_reward_applied,
      inserted_at: subscription.inserted_at,
      updated_at: subscription.updated_at
    }
  end

  defp normalize_payment(%MembershipPayment{} = payment) do
    reversed_cents = payment_reversed_cents(payment.id)

    %{
      id: payment.id,
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
      name: campaign.name,
      description: campaign.description,
      starts_on: campaign.starts_on,
      ends_on: campaign.ends_on,
      active: campaign.active,
      params: campaign.params || %{},
      inserted_at: campaign.inserted_at,
      updated_at: campaign.updated_at
    }
  end

  defp normalize_promotion_code(%PromotionCode{} = code) do
    %{
      id: code.id,
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
      name: program.name,
      description: program.description,
      active: program.active,
      reward_type: program.reward_type,
      reward_value: program.reward_value,
      params: program.params || %{},
      inserted_at: program.inserted_at,
      updated_at: program.updated_at
    }
  end

  defp normalize_referral_event(%ReferralEvent{} = event) do
    %{
      id: event.id,
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
        Date.utc_today(),
        invoice.status
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
      params: invoice.params || %{},
      inserted_at: invoice.inserted_at,
      updated_at: invoice.updated_at
    }
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

  defp string_key_map(params) when is_map(params) do
    Map.new(params, fn {key, value} -> {to_string(key), value} end)
  end
end
