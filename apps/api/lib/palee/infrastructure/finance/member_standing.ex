defmodule Palee.Infrastructure.Finance.MemberStanding do
  @moduledoc """
  ADR-274: reads the facts a member's status is worked out from, and keeps
  the values staff set by hand (`finance_value_overrides`). Runs inside the
  caller's tenant scope; `EctoFinanceStore` calls it whenever a membership's
  entitlement is refreshed, so the status follows every payment, charge,
  package, freeze and leave.
  """

  import Ecto.Query

  alias Palee.Finance.{
    FinanceInvoice,
    FinanceSubscriptionFreeze,
    FinanceValueOverride,
    Membership,
    MembershipPackageSubscription
  }

  alias Palee.Finance.Domain.{
    InvoiceLifecycle,
    MemberRenewal,
    PackageContract,
    SubscriptionCharges,
    ValueOverride
  }

  alias Palee.Infrastructure.Finance.EctoFinanceStore
  alias Palee.Infrastructure.Tenancy.RepoContext
  alias Palee.Repo

  @doc """
  The status staff set by hand that is still in force for a membership whose
  automatic status is now `computed_status`, or nil. One whose automatic
  value moved on ends here (`lapsed`).
  """
  def status_override(membership_id, computed_status) do
    case in_force(membership_id, "status") do
      nil ->
        nil

      %FinanceValueOverride{} = override ->
        if ValueOverride.lapsed?(override, computed_status) do
          end_override(override, "lapsed", nil)
          nil
        else
          override
        end
    end
  end

  @doc "What `MemberStatus.derive/1` needs to know about a membership."
  def facts(%Membership{} = membership, entitlement, %Date{} = today) do
    subscriptions =
      MembershipPackageSubscription
      |> where([s], s.membership_id == ^membership.id)
      |> Repo.all()

    %{
      today: today,
      left_at: membership.left_at,
      leaving_on: membership.leaving_on,
      membership_expires_on: membership.expires_on,
      subscriptions: Enum.map(subscriptions, &subscription_facts(&1, membership, today)),
      frozen?: frozen?(membership.id, today),
      grace_days: EctoFinanceStore.get_finance_settings().subscription_grace_days || 0,
      entitlement: %{status: entitlement.status, source: entitlement.source},
      unpaid_due_on: oldest_unpaid_due_on(membership.id, today)
    }
  end

  @doc "See `SubscriptionCharges.current_period/3`."
  defdelegate current_period(subscription, membership, today), to: SubscriptionCharges

  @doc "The override in force for a record's field, or nil."
  def in_force(subject_id, field) do
    FinanceValueOverride
    |> tenant_scope()
    |> where([o], o.subject_id == ^subject_id and o.field == ^field and is_nil(o.ended_at))
    |> Repo.one()
  end

  @doc "Every override of a membership, newest first (the change history)."
  def history(membership_id) do
    FinanceValueOverride
    |> tenant_scope()
    |> where([o], o.membership_id == ^membership_id)
    |> order_by([o], desc: o.inserted_at)
    |> Repo.all()
    |> Enum.map(&normalize/1)
  end

  @doc "The overrides in force for many memberships, by membership id."
  def in_force_by_membership(membership_ids) when is_list(membership_ids) do
    FinanceValueOverride
    |> tenant_scope()
    |> where([o], o.membership_id in ^membership_ids and is_nil(o.ended_at))
    |> Repo.all()
    |> Enum.group_by(& &1.membership_id, &normalize/1)
  end

  @doc """
  Records a value staff set by hand, replacing the one in force. The caller
  holds the membership row lock.
  """
  def put(%Membership{} = membership, field, subject_id, value, computed_value, reason, actor_id) do
    case in_force(subject_id, field) do
      nil -> :ok
      %FinanceValueOverride{} = previous -> end_override(previous, "replaced", actor_id)
    end

    %FinanceValueOverride{}
    |> FinanceValueOverride.changeset(%{
      membership_id: membership.id,
      subject_type: ValueOverride.subject_type(field),
      subject_id: subject_id,
      field: field,
      computed_value: computed_value,
      value: value,
      reason: ValueOverride.reason(reason),
      set_by_id: actor_id
    })
    |> Repo.insert()
  end

  @doc "Ends an override (`reset`, `replaced` or `lapsed`)."
  def end_override(%FinanceValueOverride{} = override, reason, actor_id) do
    override
    |> FinanceValueOverride.end_changeset(%{
      ended_at: DateTime.utc_now(),
      ended_by_id: actor_id,
      end_reason: reason
    })
    |> Repo.update!()
  end

  def normalize(%FinanceValueOverride{} = override) do
    %{
      id: override.id,
      membership_id: override.membership_id,
      subject_type: override.subject_type,
      subject_id: override.subject_id,
      field: override.field,
      computed_value: override.computed_value,
      value: override.value,
      reason: override.reason,
      set_by_id: override.set_by_id,
      set_at: override.inserted_at,
      ended_at: override.ended_at,
      ended_by_id: override.ended_by_id,
      end_reason: override.end_reason
    }
  end

  # The inclusive last day the subscription keeps if it does not renew.
  defp subscription_facts(subscription, membership, today) do
    period = SubscriptionCharges.period_at(subscription, today)

    %{
      status: subscription.status,
      starts_on: subscription.starts_on,
      ends_on: subscription.ends_on,
      price_cents_snapshot: subscription.price_cents_snapshot,
      package_type: PackageContract.type_from_params(subscription.params_snapshot || %{}),
      renews?: SubscriptionCharges.renews?(subscription, membership),
      period_last_day:
        if(SubscriptionCharges.period_months(subscription.billing_period_snapshot),
          do: SubscriptionCharges.last_day(period),
          else: nil
        ) || MemberRenewal.last_day(subscription, [], today)
    }
  end

  defp frozen?(membership_id, today) do
    FinanceSubscriptionFreeze
    |> where([f], f.membership_id == ^membership_id and is_nil(f.cancelled_at))
    |> where([f], f.starts_on <= ^today and f.ends_on >= ^today)
    |> Repo.exists?()
  end

  @doc "The oldest unpaid charge's due date per membership (only those due by `today`)."
  def oldest_unpaid_due_on_by_membership([], _today), do: %{}

  def oldest_unpaid_due_on_by_membership(membership_ids, %Date{} = today) do
    invoices =
      FinanceInvoice
      |> where([i], i.membership_id in ^membership_ids)
      |> where([i], i.status in ^InvoiceLifecycle.blocking_invoice_statuses())
      |> where([i], is_nil(i.deleted_at) and not is_nil(i.due_date) and i.due_date <= ^today)
      |> select([i], {i.id, i.membership_id, i.due_date})
      |> Repo.all()

    balances = invoices |> Enum.map(&elem(&1, 0)) |> EctoFinanceStore.invoice_balance_due_map()

    invoices
    |> Enum.filter(fn {id, _membership_id, _due} -> Map.get(balances, id, 0) > 0 end)
    |> Enum.group_by(&elem(&1, 1), &elem(&1, 2))
    |> Map.new(fn {membership_id, dates} -> {membership_id, Enum.min(dates, Date)} end)
  end

  # The oldest charge that fell due by `today` and is not paid.
  defp oldest_unpaid_due_on(membership_id, today) do
    invoices =
      FinanceInvoice
      |> where([i], i.membership_id == ^membership_id)
      |> where([i], i.status in ^InvoiceLifecycle.blocking_invoice_statuses())
      |> where([i], is_nil(i.deleted_at) and not is_nil(i.due_date) and i.due_date <= ^today)
      |> select([i], {i.id, i.due_date})
      |> Repo.all()

    balances = invoices |> Enum.map(&elem(&1, 0)) |> EctoFinanceStore.invoice_balance_due_map()

    invoices
    |> Enum.filter(fn {id, _due} -> Map.get(balances, id, 0) > 0 end)
    |> Enum.map(&elem(&1, 1))
    |> Enum.min(Date, fn -> nil end)
  end

  defp tenant_scope(queryable) do
    case RepoContext.current_setting("app.organization_id") do
      organization_id when is_binary(organization_id) and organization_id != "" ->
        from(row in queryable, where: field(row, :organization_id) == ^organization_id)

      _ ->
        from(row in queryable, where: false)
    end
  end
end
