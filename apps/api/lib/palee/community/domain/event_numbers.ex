defmodule Palee.Community.Domain.EventNumbers do
  @moduledoc """
  The organiser Events console's numbers (ADR-185 §7). Pure: callers pass
  the events, their attendees and their aggregated views.

  * **Οικονομικά.** Ticket income is what hosts recorded as paid
    («Πλήρωσε»); refunds are what they recorded as given back; net is the
    difference. Outstanding is the price of every place held on a paid,
    uncancelled event that is not paid yet. Totals are per currency, so
    events priced in different currencies never add up into a wrong sum.
  * **Αναλυτικά.** Reach is the event page's opens and distinct viewers
    (per day, so a person counted on two days counts twice). RSVPs are
    everyone who answered «Θα έρθω» (still going, waiting or later gave
    up). Attendance is who came of those holding a place, once the event
    ended. Conversion is RSVPs over distinct viewers. Rates are whole
    percentages, nil when there is nothing to divide by.
  """

  @doc "One event's money: paid, refunded, net and outstanding."
  def finances(event, attendees) do
    paid = Enum.filter(attendees, &(not is_nil(&1.paid_at)))
    refunded = Enum.filter(paid, &(not is_nil(Map.get(&1, :refunded_at))))
    paid_cents = Enum.sum(Enum.map(paid, &(&1.amount_cents || 0)))
    refunded_cents = Enum.sum(Enum.map(refunded, &(Map.get(&1, :refund_cents) || 0)))

    unpaid =
      if event.price_cents > 0 and is_nil(event.cancelled_at),
        do: Enum.count(attendees, &(&1.status == "going" and is_nil(&1.paid_at))),
        else: 0

    %{
      currency: event.currency,
      price_cents: event.price_cents,
      paid_count: length(paid),
      paid_cents: paid_cents,
      refunded_count: length(refunded),
      refunded_cents: refunded_cents,
      net_cents: paid_cents - refunded_cents,
      outstanding_count: unpaid,
      outstanding_cents: unpaid * event.price_cents
    }
  end

  @doc "Totals of many events' money, one row per currency (sorted)."
  def finance_totals(rows) do
    rows
    |> Enum.group_by(& &1.currency)
    |> Enum.map(fn {currency, list} ->
      Enum.reduce(
        list,
        %{
          currency: currency,
          events: 0,
          paid_count: 0,
          paid_cents: 0,
          refunded_count: 0,
          refunded_cents: 0,
          net_cents: 0,
          outstanding_count: 0,
          outstanding_cents: 0
        },
        fn row, acc ->
          acc
          |> Map.update!(:events, &(&1 + 1))
          |> add(row, ~w(paid_count paid_cents refunded_count refunded_cents net_cents
                         outstanding_count outstanding_cents)a)
        end
      )
    end)
    |> Enum.sort_by(& &1.currency)
  end

  @doc """
  One event's reach and response. `views` are `%{views, viewers}` summed
  over its days.
  """
  def analytics(event, attendees, views, now) do
    going = Enum.filter(attendees, &(&1.status == "going"))
    came = Enum.count(going, &(not is_nil(&1.checked_in_at)))
    over? = DateTime.compare(event.ends_at, now) != :gt
    viewers = Map.get(views, :viewers, 0)
    rsvps = length(attendees)

    %{
      views: Map.get(views, :views, 0),
      viewers: viewers,
      rsvps: rsvps,
      going: length(going),
      waitlisted: Enum.count(attendees, &(&1.status == "waitlisted")),
      cancelled: Enum.count(attendees, &(&1.status == "cancelled")),
      came: came,
      attendance_rate: if(over?, do: percent(came, length(going))),
      conversion_rate: percent(rsvps, viewers)
    }
  end

  @doc "Totals of many events' analytics, with the rates over the totals."
  def analytics_totals(rows) do
    sums =
      Enum.reduce(
        rows,
        %{events: 0, views: 0, viewers: 0, rsvps: 0, going: 0, waitlisted: 0, came: 0},
        fn row, acc ->
          acc
          |> Map.update!(:events, &(&1 + 1))
          |> add(row, ~w(views viewers rsvps going waitlisted came)a)
        end
      )

    ended = Enum.filter(rows, &(not is_nil(&1.attendance_rate)))

    Map.merge(sums, %{
      attendance_rate:
        percent(Enum.sum(Enum.map(ended, & &1.came)), Enum.sum(Enum.map(ended, & &1.going))),
      conversion_rate: percent(sums.rsvps, sums.viewers)
    })
  end

  @doc "A whole percentage of `part` over `whole`, capped at 100; nil over nothing."
  def percent(_part, whole) when whole in [0, nil], do: nil
  def percent(part, whole), do: min(round(part * 100 / whole), 100)

  defp add(acc, row, keys), do: Enum.reduce(keys, acc, &Map.update!(&2, &1, fn v -> v + Map.fetch!(row, &1) end))
end
