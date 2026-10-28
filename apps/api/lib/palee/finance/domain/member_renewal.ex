defmodule Palee.Finance.Domain.MemberRenewal do
  @moduledoc """
  Pure rules for the member's renewal choice and leaving the box (ADR-220).

  A package's `terms.auto_renew` says whether its subscriptions *may* renew;
  each subscription carries the member's own choice (`auto_renew`). Turning
  it off never takes away what was paid for: the subscription keeps going to
  the end of its current billing period (or a later paid period, or the end
  of a minimum commitment) and ends there through the usual expiry, grace
  and access-ended flow. While it is off no renewal invoice is issued.

  Leaving the box turns renewal off everywhere and sets the membership's
  last day. Only what lies after it is cancelled: unpaid invoices for
  periods that begin later and for packages that never started. Money owed
  for anything already used stays owed, shown and reminded until paid.
  """

  alias Palee.Finance.Domain.{InvoiceLifecycle, SubscriptionSelection}

  @recurring_periods ~w(monthly quarterly annual)
  @paid_statuses ~w(paid partially_paid)
  @unpaid_statuses ~w(draft issued overdue)

  @doc """
  Whether the member may choose about renewing this subscription: an active,
  recurring subscription of a package that allows renewal, that they hold
  themselves (an add-on follows its base; a company pays for a corporate seat).
  """
  def choice_allowed?(subscription) do
    field(subscription, :status) == "active" and
      is_nil(field(subscription, :base_subscription_id)) and
      is_nil(field(subscription, :corporate_client_id)) and
      SubscriptionSelection.renewable?(field(subscription, :params_snapshot) || %{}) == :ok
  end

  @doc "The member's effective choice: nil when they have none to make."
  def auto_renew(subscription) do
    if choice_allowed?(subscription), do: field(subscription, :auto_renew) != false, else: nil
  end

  @doc "A renewal invoice may be issued only while the member keeps renewal on."
  def renewal_allowed(subscription, membership) do
    cond do
      field(subscription, :auto_renew) == false -> {:error, :renewal_turned_off}
      membership && field(membership, :left_at) -> {:error, :member_leaving}
      true -> :ok
    end
  end

  @doc """
  Inclusive last day a subscription keeps when renewal stops `today`: the end
  of the current billing period, of a later period already paid for, or of
  the minimum commitment, whichever is latest; never before `today`. A
  subscription with its own end date (a validity) keeps that date.

  `paid_periods` are `{service_period_start, service_period_end}` pairs of
  the subscription's paid (or partly paid) invoices.
  """
  def last_day(subscription, paid_periods, %Date{} = today) do
    case field(subscription, :ends_on) do
      %Date{} = ends_on ->
        if field(subscription, :ends_on_from_renewal_stop),
          do: open_ended_last_day(subscription, paid_periods, today),
          else: ends_on

      nil ->
        open_ended_last_day(subscription, paid_periods, today)
    end
  end

  defp open_ended_last_day(subscription, paid_periods, today) do
    [
      today,
      period_last_day(subscription, today),
      field(subscription, :commitment_ends_on)
      | Enum.map(paid_periods, &paid_through/1)
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.max(Date)
  end

  # The last day of the billing period `today` falls in, counted from the
  # subscription's start in whole periods (so 31 January stays the anchor).
  defp period_last_day(subscription, today) do
    period = field(subscription, :billing_period_snapshot)
    starts_on = field(subscription, :starts_on) || today

    if period in @recurring_periods do
      months = %{"monthly" => 1, "quarterly" => 3, "annual" => 12}[period]

      Stream.iterate(1, &(&1 + 1))
      |> Stream.map(&Date.shift(starts_on, month: &1 * months))
      |> Enum.find(&(Date.compare(&1, today) == :gt))
      |> Date.add(-1)
    end
  end

  # A service period's end is read as inclusive, so a paid period is never
  # cut short by a day.
  defp paid_through({_starts_on, %Date{} = ends_on}), do: ends_on
  defp paid_through(_period), do: nil

  @doc "The paid (or partly paid) invoice statuses that keep a period."
  def paid_statuses, do: @paid_statuses

  @doc """
  Invoices that stop being owed when the member's last day is `last_day`:
  unpaid, with nothing paid or credited, for a service period that starts
  after it. Each invoice is a map with `:status`, `:service_period_start`,
  `:paid_cents` and `:credit_applied_cents`.
  """
  def void_after_leaving?(invoice, %Date{} = last_day) do
    starts_on = field(invoice, :service_period_start)

    field(invoice, :status) in @unpaid_statuses and untouched?(invoice) and
      match?(%Date{}, starts_on) and Date.compare(starts_on, last_day) == :gt
  end

  @doc "An open invoice nothing was paid or credited on."
  def unpaid_untouched?(invoice),
    do: field(invoice, :status) in @unpaid_statuses and untouched?(invoice)

  defp untouched?(invoice),
    do:
      (field(invoice, :paid_cents) || 0) == 0 and
        (field(invoice, :credit_applied_cents) || 0) == 0

  @doc """
  The day a member leaving `today` keeps access until: the latest last day
  of the subscriptions they hold (`last_days`), or today when they hold none.
  """
  def leaving_on([], %Date{} = today), do: today
  def leaving_on(last_days, %Date{} = today), do: Enum.max([today | last_days], Date)

  @doc """
  Staff choosing a last day before a minimum commitment ends need a reason,
  like cancelling (ADR-097).
  """
  def staff_leaving_allowed(%Date{} = leaving_on, commitment_ends_on, override_reason) do
    cond do
      is_nil(commitment_ends_on) -> :ok
      Date.compare(leaving_on, commitment_ends_on) != :lt -> :ok
      is_binary(override_reason) and String.trim(override_reason) != "" -> :ok
      true -> {:error, :package_commitment_active}
    end
  end

  @doc "Whether the leave can still be undone: the last day has not passed."
  def undo_allowed(membership, %Date{} = today) do
    case field(membership, :leaving_on) do
      nil ->
        {:error, :not_leaving}

      leaving_on ->
        if Date.compare(leaving_on, today) == :lt, do: {:error, :already_left}, else: :ok
    end
  end

  @doc "Whether a subscription is still running on `today` (renewal can be turned back on)."
  def running?(subscription, %Date{} = today) do
    InvoiceLifecycle.subscription_active?(
      field(subscription, :status),
      nil,
      field(subscription, :ends_on),
      today
    )
  end

  defp field(map, key) do
    case Map.fetch(map, key) do
      {:ok, value} -> value
      :error -> Map.get(map, Atom.to_string(key))
    end
  end
end
