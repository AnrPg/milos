defmodule Palee.Finance.Domain.SubscriptionCharges do
  @moduledoc """
  ADR-274: what a subscription owes, period by period. Pure rules; the store
  does the writing.

  Every subscription with a price owes money for each period it runs, so
  Palee issues a charge (a Finance invoice, never a legal document: the
  fiscal document is issued with the payment, ADR-262) when a period
  begins:

    * a recurring package (monthly, quarterly, semiannual, annual) owes one
      charge per period, counted in whole periods from `starts_on` (so 31
      January stays the anchor). A period is `{start, next_start}`, the same
      shape renewal invoices always had; its last day is `next_start - 1`;
    * any other package (a class pack, a trial, a custom or add-on period)
      owes one charge for the whole subscription.

  The first period's charge is a `"subscription"` invoice and every later
  one a `"renewal"` invoice, so renewal figures keep their meaning.

  `charges_from` on the subscription is the first period start Palee bills
  by itself (nil: never, e.g. a corporate seat or a free package). Money
  already recorded for the subscription before its first charge (a desk
  receipt, an online purchase) counts against that charge.
  """

  alias Palee.Finance.Domain.SubscriptionSelection

  @period_months %{"monthly" => 1, "quarterly" => 3, "semiannual" => 6, "annual" => 12}

  @doc "Months in a recurring billing period, or nil for a one-charge package."
  def period_months(billing_period), do: Map.get(@period_months, billing_period)

  @doc "Whether the subscription is billed by Palee at all."
  def billable?(subscription) do
    price = field(subscription, :price_cents_snapshot) || 0

    price > 0 and is_nil(field(subscription, :corporate_client_id)) and
      match?(%Date{}, field(subscription, :starts_on))
  end

  @doc "The first period start Palee bills for a newly assigned subscription."
  def charges_from(subscription) do
    if billable?(subscription), do: field(subscription, :starts_on), else: nil
  end

  @doc """
  The period of a subscription that contains `date`: `{start, next_start}`
  for a recurring package, `{starts_on, ends_on + 1}` (or `{starts_on, nil}`
  while it has no end) for the others. Nil before the subscription starts.
  """
  def period_at(subscription, %Date{} = date) do
    starts_on = field(subscription, :starts_on)

    cond do
      not match?(%Date{}, starts_on) or Date.compare(date, starts_on) == :lt ->
        nil

      months = period_months(field(subscription, :billing_period_snapshot)) ->
        index = whole_periods(starts_on, date, months)
        {shift(starts_on, index * months), shift(starts_on, (index + 1) * months)}

      true ->
        {starts_on, next_day(field(subscription, :ends_on))}
    end
  end

  @doc """
  The period a subscription is in on `today` (the first one before it
  starts): `%{starts_on, ends_on, renews}`, where `ends_on` is the inclusive
  last day «Λήγει» shows and `renews` says whether another period follows.
  A subscription with its own end date ends on it.
  """
  def current_period(subscription, membership, %Date{} = today) do
    period = period_at(subscription, today) || first_period(subscription)

    cond do
      match?(%Date{}, field(subscription, :ends_on)) ->
        %{
          starts_on: period && elem(period, 0),
          ends_on: field(subscription, :ends_on),
          renews: false
        }

      period ->
        %{
          starts_on: elem(period, 0),
          ends_on: last_day(period),
          renews:
            renews?(subscription, membership) and
              period_months(field(subscription, :billing_period_snapshot)) != nil
        }

      true ->
        nil
    end
  end

  @doc """
  Whether a subscription renews after its current period: it runs, the
  package allows renewal, the member keeps it on and is not leaving (ADR-220).
  """
  def renews?(subscription, membership) do
    field(subscription, :status) == "active" and field(subscription, :auto_renew) != false and
      SubscriptionSelection.renewable?(field(subscription, :params_snapshot) || %{}) == :ok and
      not match?(%DateTime{}, field(membership, :left_at))
  end

  defp first_period(subscription) do
    case field(subscription, :starts_on) do
      %Date{} = starts_on -> period_at(subscription, starts_on)
      _none -> nil
    end
  end

  @doc "The inclusive last day of a period (nil while it has no end)."
  def last_day({_start, %Date{} = next_start}), do: Date.add(next_start, -1)
  def last_day(_period), do: nil

  @doc """
  The periods a subscription owes on `today` that have no charge yet: every
  period that has begun since `charges_from` (and before the subscription's
  end), oldest first, minus the ones in `charged_starts`.

  `renews?` says whether a period after the first may still be billed (the
  member keeps renewal on and is not leaving before it, ADR-220).
  """
  def due_periods(subscription, charged_starts, %Date{} = today, renews?)
      when is_function(renews?, 1) do
    with %Date{} = from <- field(subscription, :charges_from),
         true <- billable?(subscription),
         true <- field(subscription, :status) == "active" do
      charged = MapSet.new(charged_starts)

      subscription
      |> periods_between(from, today)
      |> Enum.reject(fn {start, _next} -> MapSet.member?(charged, start) end)
      |> Enum.filter(fn {start, _next} ->
        first_period?(subscription, start) or renews?.(start)
      end)
    else
      _other -> []
    end
  end

  @doc "Whether `start` begins the subscription's first period."
  def first_period?(subscription, %Date{} = start),
    do: field(subscription, :starts_on) == start

  @doc "The invoice type of a period's charge."
  def invoice_type(subscription, start),
    do: if(first_period?(subscription, start), do: "subscription", else: "renewal")

  @doc """
  The amount still to charge for a period once money recorded for it
  without a charge is counted: never below zero.
  """
  def amount_due(subscription, accounted_cents) when is_integer(accounted_cents),
    do: max((field(subscription, :price_cents_snapshot) || 0) - accounted_cents, 0)

  @doc """
  Whether a document recorded for the subscription (not a charge of
  Palee's) pays for the period beginning `start`: one for that very period,
  or one without a period, issued in it (any time for the first period).
  """
  def accounts_for?(subscription, document, %Date{} = start) do
    case field(document, :service_period_start) do
      %Date{} = period_start ->
        period_start == start

      nil ->
        first_period?(subscription, start) or
          case field(document, :issue_date) do
            %Date{} = issued -> Date.compare(issued, start) != :lt
            _other -> false
          end
    end
  end

  defp periods_between(subscription, %Date{} = from, %Date{} = today) do
    ends_on = field(subscription, :ends_on)

    last =
      if match?(%Date{}, ends_on) and Date.compare(ends_on, today) == :lt,
        do: ends_on,
        else: today

    case period_months(field(subscription, :billing_period_snapshot)) do
      nil ->
        starts_on = field(subscription, :starts_on)

        if Date.compare(from, starts_on) != :gt and Date.compare(starts_on, today) != :gt,
          do: [{starts_on, next_day(ends_on)}],
          else: []

      months ->
        Stream.iterate(0, &(&1 + 1))
        |> Stream.map(fn index ->
          {shift(field(subscription, :starts_on), index * months),
           shift(field(subscription, :starts_on), (index + 1) * months)}
        end)
        |> Stream.take_while(fn {start, _next} -> Date.compare(start, last) != :gt end)
        |> Enum.filter(fn {start, _next} -> Date.compare(start, from) != :lt end)
    end
  end

  defp whole_periods(starts_on, date, months) do
    Stream.iterate(0, &(&1 + 1))
    |> Enum.find(fn index ->
      Date.compare(shift(starts_on, (index + 1) * months), date) == :gt
    end)
  end

  defp shift(date, months), do: Date.shift(date, month: months)

  defp next_day(%Date{} = date), do: Date.add(date, 1)
  defp next_day(_date), do: nil

  defp field(map, key) when is_map(map),
    do: Map.get(map, key, Map.get(map, Atom.to_string(key)))

  defp field(_map, _key), do: nil
end
