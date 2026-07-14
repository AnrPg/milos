defmodule MilosTraining.Finance.Domain.MemberDrillDown do
  @moduledoc false

  @expiring_window_days 30

  def build(user, profile, today \\ Date.utc_today()) do
    profile = normalize_profile(profile)
    membership = Map.get(profile, :membership)
    entitlement = Map.get(profile, :entitlement) || %{}
    active_subscription = Map.get(profile, :active_package_subscription)

    %{
      identity: identity_summary(user, membership),
      current_status: current_status(membership, entitlement, today),
      package_relationship:
        package_relationship(membership, active_subscription, profile.package_subscriptions),
      financial_timeline: financial_timeline(profile),
      outstanding_items: outstanding_items(membership, active_subscription, profile, today),
      operational_context: operational_context(membership, profile, today),
      actions: actions(membership, active_subscription, profile)
    }
  end

  defp normalize_profile(nil), do: %{}

  defp normalize_profile(profile) when is_map(profile) do
    profile
    |> Map.put_new(:package_subscriptions, [])
    |> Map.put_new(:payments, [])
    |> Map.put_new(:payment_reversals, [])
    |> Map.put_new(:promotion_redemptions, [])
    |> Map.put_new(:credit_ledger_entries, [])
    |> Map.put_new(:invoices, [])
    |> Map.put_new(:credit_balance, 0)
  end

  defp identity_summary(user, membership) do
    %{
      user_id: field(user, :id),
      nickname: field(user, :nickname),
      role: role_string(field(user, :role)),
      user_type: field(membership, :user_type_snapshot) || role_string(field(user, :role))
    }
  end

  defp current_status(nil, _entitlement, _today) do
    %{
      state: "unmanaged",
      reason: "membership_profile_missing",
      membership_status: nil,
      entitlement_status: "unmanaged",
      entitlement_source: nil,
      starts_on: nil,
      expires_on: nil,
      days_until_expiry: nil,
      urgency: "attention"
    }
  end

  defp current_status(membership, entitlement, today) do
    expires_on = field(membership, :expires_on)
    days_until_expiry = days_until(expires_on, today)
    membership_status = field(membership, :status)
    entitlement_status = field(entitlement, :status) || field(membership, :entitlement_status)
    entitlement_source = field(entitlement, :source) || field(membership, :entitlement_source)

    %{
      state: membership_status || "unknown",
      reason: status_reason(membership_status, entitlement_status, entitlement_source),
      membership_status: membership_status,
      entitlement_status: entitlement_status,
      entitlement_source: entitlement_source,
      starts_on: field(membership, :starts_on),
      expires_on: expires_on,
      days_until_expiry: days_until_expiry,
      urgency: urgency(membership_status, entitlement, days_until_expiry)
    }
  end

  defp package_relationship(nil, _active_subscription, _subscriptions) do
    %{
      status: "unassigned",
      reason: "membership_profile_required",
      current_package: nil,
      subscriptions: []
    }
  end

  defp package_relationship(_membership, nil, subscriptions) do
    %{
      status: "unassigned",
      reason: "no_active_package",
      current_package: nil,
      subscriptions: subscriptions
    }
  end

  defp package_relationship(_membership, active_subscription, subscriptions) do
    subscriptions =
      case subscriptions do
        [] -> [active_subscription]
        subscriptions -> subscriptions
      end

    %{
      status: field(active_subscription, :status) || "active",
      reason: "active_package_subscription",
      current_package: %{
        subscription_id: field(active_subscription, :id),
        package_id: field(active_subscription, :membership_package_id),
        code: field(active_subscription, :package_code_snapshot),
        family: field(active_subscription, :package_family_snapshot),
        billing_period: field(active_subscription, :billing_period_snapshot),
        price_cents: field(active_subscription, :price_cents_snapshot),
        starts_on: field(active_subscription, :starts_on),
        ends_on: field(active_subscription, :ends_on)
      },
      subscriptions: subscriptions
    }
  end

  defp financial_timeline(profile) do
    []
    |> Kernel.++(Enum.map(profile.invoices, &invoice_event/1))
    |> Kernel.++(Enum.map(profile.credit_ledger_entries, &credit_event/1))
    |> Kernel.++(Enum.map(profile.payments, &payment_event/1))
    |> Kernel.++(Enum.map(profile.payment_reversals, &payment_reversal_event/1))
    |> Kernel.++(Enum.map(profile.promotion_redemptions, &promotion_event/1))
    |> Enum.sort_by(&timeline_sort_value/1, {:desc, DateTime})
  end

  defp invoice_event(invoice) do
    %{
      type: "invoice",
      id: field(invoice, :id),
      occurred_at: event_time(invoice, [:inserted_at, :updated_at, :issue_date, :due_date]),
      label: field(invoice, :invoice_number) || field(invoice, :invoice_type) || "Invoice",
      status: field(invoice, :status),
      amount_cents: field(invoice, :total_cents) || 0,
      balance_due_cents: field(invoice, :balance_due_cents) || 0,
      due_date: field(invoice, :due_date)
    }
  end

  defp credit_event(entry) do
    %{
      type: "credit",
      id: field(entry, :id),
      occurred_at: event_time(entry, [:occurred_at, :inserted_at, :occurred_on]),
      label: field(entry, :description) || field(entry, :source_type) || "Credit",
      status: field(entry, :entry_type),
      amount_cents: field(entry, :amount_cents) || 0,
      source_type: field(entry, :source_type)
    }
  end

  defp payment_event(payment) do
    %{
      type: "payment",
      id: field(payment, :id),
      occurred_at: event_time(payment, [:inserted_at, :paid_on, :updated_at]),
      label: field(payment, :payment_method) || "Payment",
      status: field(payment, :payment_status),
      amount_cents: field(payment, :amount_cents) || 0,
      net_amount_cents: field(payment, :net_amount_cents) || field(payment, :amount_cents) || 0
    }
  end

  defp payment_reversal_event(reversal) do
    %{
      type: "payment_reversal",
      id: field(reversal, :id),
      occurred_at: event_time(reversal, [:occurred_at, :inserted_at, :occurred_on]),
      label: field(reversal, :reason) || field(reversal, :reversal_type) || "Payment reversal",
      status: field(reversal, :reversal_type),
      amount_cents: field(reversal, :amount_cents) || 0
    }
  end

  defp promotion_event(redemption) do
    %{
      type: "promotion_redemption",
      id: field(redemption, :id),
      occurred_at: event_time(redemption, [:redeemed_at, :inserted_at]),
      label: field(redemption, :discount_type_snapshot) || "Promotion",
      status: "redeemed",
      amount_cents: 0,
      discount_type: field(redemption, :discount_type_snapshot),
      discount_value: field(redemption, :discount_value_snapshot)
    }
  end

  defp outstanding_items(nil, _active_subscription, _profile, _today) do
    [
      %{
        type: "membership_profile_missing",
        severity: "medium",
        reason: "membership_profile_required",
        title: "Membership profile missing"
      }
    ]
  end

  defp outstanding_items(membership, active_subscription, profile, today) do
    []
    |> maybe_add_no_package(active_subscription)
    |> Kernel.++(invoice_items(profile.invoices, today))
    |> maybe_add_expiry_item(membership, today)
    |> Enum.sort_by(&item_sort/1)
  end

  defp maybe_add_no_package(items, nil) do
    [
      %{
        type: "package_unassigned",
        severity: "medium",
        reason: "no_active_package",
        title: "No active package"
      }
      | items
    ]
  end

  defp maybe_add_no_package(items, _subscription), do: items

  defp invoice_items(invoices, today) do
    invoices
    |> Enum.filter(fn invoice ->
      (field(invoice, :balance_due_cents) || 0) > 0 and
        field(invoice, :status) in ["issued", "partially_paid", "overdue"]
    end)
    |> Enum.map(fn invoice ->
      overdue? =
        overdue?(field(invoice, :due_date), today) || field(invoice, :status) == "overdue"

      %{
        type: if(overdue?, do: "overdue_invoice", else: "open_invoice"),
        severity: if(overdue?, do: "high", else: "medium"),
        reason: if(overdue?, do: "invoice_overdue", else: "invoice_open"),
        title: if(overdue?, do: "Overdue invoice", else: "Open invoice"),
        invoice_id: field(invoice, :id),
        due_date: field(invoice, :due_date),
        amount_cents: field(invoice, :balance_due_cents) || 0
      }
    end)
  end

  defp maybe_add_expiry_item(items, membership, today) do
    expires_on = field(membership, :expires_on)

    case days_until(expires_on, today) do
      nil ->
        items

      days when days < 0 ->
        [
          %{
            type: "membership_expired",
            severity: "high",
            reason: "membership_expired",
            title: "Membership expired",
            due_date: expires_on
          }
          | items
        ]

      days when days <= @expiring_window_days ->
        [
          %{
            type: "membership_expiring",
            severity: if(days <= 7, do: "high", else: "medium"),
            reason: "membership_expiring",
            title: "Membership expiring",
            due_date: expires_on,
            days_until_expiry: days
          }
          | items
        ]

      _days ->
        items
    end
  end

  defp operational_context(membership, profile, today) do
    %{
      notes: field(membership, :notes),
      signup_source: field(membership, :signup_source),
      credit_balance_cents: Map.get(profile, :credit_balance) || 0,
      open_invoice_count:
        count_invoices(profile.invoices, ["issued", "partially_paid", "overdue"]),
      overdue_invoice_count: count_overdue_invoices(profile.invoices, today),
      last_payment: List.first(profile.payments)
    }
  end

  defp actions(nil, _active_subscription, _profile) do
    [
      action("update_membership", true),
      action("assign_package", false, "membership_profile_required"),
      action("renew_membership", false, "membership_profile_required"),
      action("cancel_membership", false, "membership_profile_required"),
      action("record_payment", false, "membership_profile_required"),
      action("create_invoice", false, "membership_profile_required"),
      action("create_manual_credit", false, "membership_profile_required")
    ]
  end

  defp actions(membership, active_subscription, _profile) do
    cancelled? = field(membership, :status) == "cancelled"
    has_active_subscription? = not is_nil(active_subscription)

    [
      action("update_membership", true),
      action("assign_package", true),
      action(
        "renew_membership",
        has_active_subscription? and not cancelled?,
        if(has_active_subscription?, do: "membership_cancelled", else: "active_package_required")
      ),
      action("cancel_membership", not cancelled?, "already_cancelled"),
      action("record_payment", true),
      action("create_invoice", true),
      action("create_manual_credit", true)
    ]
  end

  defp action(key, true), do: %{key: key, available: true, reason: nil}
  defp action(key, false, reason), do: %{key: key, available: false, reason: reason}

  defp action(key, available, reason) do
    if available, do: action(key, true), else: action(key, false, reason)
  end

  defp status_reason("cancelled", _entitlement_status, _entitlement_source),
    do: "membership_cancelled"

  defp status_reason("paused", _entitlement_status, _entitlement_source), do: "membership_paused"

  defp status_reason("expired", _entitlement_status, _entitlement_source),
    do: "membership_expired"

  defp status_reason(_membership_status, "blocked", "overdue_invoice"), do: "invoice_overdue"
  defp status_reason(_membership_status, "grace", "open_invoice"), do: "open_invoice"

  defp status_reason(membership_status, _entitlement_status, _entitlement_source),
    do: membership_status || "unknown"

  defp urgency(_membership_status, entitlement, days_until_expiry) do
    cond do
      (field(entitlement, :overdue_invoice_count) || 0) > 0 -> "urgent"
      is_integer(days_until_expiry) and days_until_expiry <= 7 -> "urgent"
      (field(entitlement, :open_invoice_count) || 0) > 0 -> "attention"
      is_integer(days_until_expiry) and days_until_expiry <= @expiring_window_days -> "attention"
      true -> "normal"
    end
  end

  defp count_invoices(invoices, statuses) do
    Enum.count(
      invoices,
      &(field(&1, :status) in statuses and (field(&1, :balance_due_cents) || 0) > 0)
    )
  end

  defp count_overdue_invoices(invoices, today) do
    Enum.count(
      invoices,
      &((field(&1, :status) == "overdue" or overdue?(field(&1, :due_date), today)) and
          (field(&1, :balance_due_cents) || 0) > 0)
    )
  end

  defp overdue?(nil, _today), do: false
  defp overdue?(due_date, today), do: Date.compare(due_date, today) == :lt

  defp days_until(nil, _today), do: nil
  defp days_until(%Date{} = date, today), do: Date.diff(date, today)
  defp days_until(_value, _today), do: nil

  defp field(nil, _key), do: nil
  defp field(map, key) when is_map(map), do: Map.get(map, key) || Map.get(map, to_string(key))

  defp role_string(nil), do: nil
  defp role_string(role), do: to_string(role)

  defp event_time(map, keys) do
    keys
    |> Enum.map(&field(map, &1))
    |> Enum.find(& &1)
    |> normalize_event_time()
  end

  defp normalize_event_time(%DateTime{} = date_time), do: date_time

  defp normalize_event_time(%NaiveDateTime{} = date_time),
    do: DateTime.from_naive!(date_time, "Etc/UTC")

  defp normalize_event_time(%Date{} = date), do: DateTime.new!(date, ~T[00:00:00], "Etc/UTC")
  defp normalize_event_time(_value), do: DateTime.from_unix!(0)

  defp timeline_sort_value(%{occurred_at: %DateTime{} = date_time}), do: date_time
  defp timeline_sort_value(_event), do: DateTime.from_unix!(0)

  defp severity_sort(%{severity: "high"}), do: 0
  defp severity_sort(%{severity: "medium"}), do: 1
  defp severity_sort(_item), do: 2

  defp item_sort(item), do: {severity_sort(item), item_type_sort(field(item, :type))}

  defp item_type_sort("overdue_invoice"), do: 0
  defp item_type_sort("open_invoice"), do: 1
  defp item_type_sort("membership_expired"), do: 2
  defp item_type_sort("membership_expiring"), do: 3
  defp item_type_sort(_type), do: 9
end
