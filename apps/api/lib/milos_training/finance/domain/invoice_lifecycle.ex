defmodule MilosTraining.Finance.Domain.InvoiceLifecycle do
  @active_membership_statuses ["active", "trial", "expiring", "comped"]
  @active_subscription_statuses ["active"]
  @blocking_invoice_statuses ["issued", "partially_paid", "overdue"]

  def line_total(quantity, unit_amount_cents, discount_cents \\ 0)

  def line_total(quantity, unit_amount_cents, discount_cents)
      when is_integer(quantity) and is_integer(unit_amount_cents) and is_integer(discount_cents) do
    subtotal_cents = quantity * unit_amount_cents

    cond do
      quantity <= 0 or unit_amount_cents < 0 or discount_cents < 0 ->
        {:error, :invalid_invoice_line_amount}

      discount_cents > subtotal_cents ->
        {:error, :invoice_line_discount_exceeds_subtotal}

      true ->
        {:ok, subtotal_cents - discount_cents}
    end
  end

  def line_total(_quantity, _unit_amount_cents, _discount_cents),
    do: {:error, :invalid_invoice_line_amount}

  def invoice_totals(lines) when is_list(lines) do
    subtotal =
      Enum.reduce(lines, 0, fn line, acc ->
        acc +
          (line[:quantity] || line["quantity"] || 1) *
            (line[:unit_amount_cents] || line["unit_amount_cents"] || 0)
      end)

    discount =
      Enum.reduce(lines, 0, fn line, acc ->
        acc + (line[:discount_cents] || line["discount_cents"] || 0)
      end)

    total =
      Enum.reduce(lines, 0, fn line, acc ->
        acc + (line[:total_cents] || line["total_cents"] || 0)
      end)

    %{subtotal_cents: subtotal, discount_cents: discount, total_cents: total}
  end

  def validate_credit_application(status, available_cents, amount_cents, remaining_due_cents) do
    cond do
      status == "draft" -> {:error, :invoice_not_issued}
      status == "void" -> {:error, :invoice_void}
      status == "paid" -> {:error, :invoice_already_paid}
      amount_cents <= 0 -> {:error, :invalid_credit_amount}
      amount_cents > available_cents -> {:error, :insufficient_credit_balance}
      amount_cents > remaining_due_cents -> {:error, :credit_exceeds_invoice_balance}
      true -> :ok
    end
  end

  def validate_payment_application(status, amount_cents, remaining_due_cents) do
    cond do
      status == "draft" -> {:error, :invoice_not_issued}
      status == "void" -> {:error, :invoice_void}
      status == "paid" -> {:error, :invoice_already_paid}
      amount_cents <= 0 -> {:error, :invalid_payment_amount}
      amount_cents > remaining_due_cents -> {:error, :payment_exceeds_invoice_balance}
      true -> :ok
    end
  end

  def validate_void(status, paid_cents, credit_applied_cents) do
    cond do
      status == "void" -> {:error, :invoice_void}
      paid_cents > 0 or credit_applied_cents > 0 -> {:error, :invoice_has_allocations}
      true -> :ok
    end
  end

  def validate_payment_reversal(
        status,
        payment_amount_cents,
        already_reversed_cents,
        amount_cents
      )
      when is_integer(payment_amount_cents) and is_integer(already_reversed_cents) and
             is_integer(amount_cents) do
    remaining_cents = payment_amount_cents - already_reversed_cents

    cond do
      status not in ["paid", "waived"] -> {:error, :payment_not_reversible}
      amount_cents <= 0 -> {:error, :invalid_payment_reversal_amount}
      amount_cents > remaining_cents -> {:error, :payment_reversal_exceeds_payment_amount}
      true -> :ok
    end
  end

  def validate_payment_reversal(
        _status,
        _payment_amount_cents,
        _already_reversed_cents,
        _amount_cents
      ),
      do: {:error, :invalid_payment_reversal_amount}

  def status(total_cents, paid_cents, credit_applied_cents, due_date, today, current_status)

  def status(_total_cents, _paid_cents, _credit_applied_cents, _due_date, _today, "void"),
    do: "void"

  def status(total_cents, paid_cents, credit_applied_cents, due_date, today, _current_status) do
    applied_cents = paid_cents + credit_applied_cents

    cond do
      total_cents <= 0 -> "paid"
      applied_cents >= total_cents -> "paid"
      due_date && Date.compare(today, due_date) == :gt -> "overdue"
      applied_cents > 0 -> "partially_paid"
      true -> "issued"
    end
  end

  def entitlement(%{
        membership_status: membership_status,
        membership_expires_on: membership_expires_on,
        active_subscription?: active_subscription?,
        open_invoice_count: open_invoice_count,
        overdue_invoice_count: overdue_invoice_count,
        today: today
      }) do
    cond do
      membership_status in ["cancelled", "paused", "expired"] ->
        %{status: "inactive", source: "membership_status", expires_on: membership_expires_on}

      membership_expires_on && Date.compare(membership_expires_on, today) == :lt ->
        %{status: "inactive", source: "membership_expired", expires_on: membership_expires_on}

      overdue_invoice_count > 0 ->
        %{status: "blocked", source: "overdue_invoice", expires_on: membership_expires_on}

      open_invoice_count > 0 and membership_status in @active_membership_statuses ->
        %{status: "grace", source: "open_invoice", expires_on: membership_expires_on}

      active_subscription? and membership_status in @active_membership_statuses ->
        %{status: "active", source: "membership_package", expires_on: membership_expires_on}

      membership_status in ["trial", "comped"] ->
        %{status: "active", source: membership_status, expires_on: membership_expires_on}

      true ->
        %{status: "inactive", source: "no_active_package", expires_on: membership_expires_on}
    end
  end

  def active_subscription_statuses, do: @active_subscription_statuses
  def blocking_invoice_statuses, do: @blocking_invoice_statuses

  def next_period("monthly", starts_on), do: {starts_on, Date.shift(starts_on, month: 1)}
  def next_period("quarterly", starts_on), do: {starts_on, Date.shift(starts_on, month: 3)}
  def next_period("annual", starts_on), do: {starts_on, Date.shift(starts_on, year: 1)}

  def renewal_period("custom", starts_on, %Date{} = ends_on) do
    if Date.compare(ends_on, starts_on) == :gt do
      {:ok, {starts_on, ends_on}}
    else
      {:error, :invalid_renewal_period}
    end
  end

  def renewal_period("custom", _starts_on, _ends_on),
    do: {:error, :invalid_renewal_period}

  def renewal_period(billing_period, starts_on, _ends_on)
      when billing_period in ["monthly", "quarterly", "annual"],
      do: {:ok, next_period(billing_period, starts_on)}

  def renewal_period(_billing_period, _starts_on, _ends_on),
    do: {:error, :invalid_billing_period}

  def subscription_active?(status, starts_on, ends_on, today) do
    status in @active_subscription_statuses and
      (is_nil(starts_on) or Date.compare(starts_on, today) != :gt) and
      (is_nil(ends_on) or Date.compare(ends_on, today) != :lt)
  end
end
