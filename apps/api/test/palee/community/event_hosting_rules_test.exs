defmodule Palee.Community.EventHostingRulesTest do
  @moduledoc "ADR-185: the pure rules of hosting, co-hosting and the console's numbers."

  use ExUnit.Case, async: true

  alias Palee.Community.Domain.{CohostPolicy, EventNumbers, HostPolicy}

  @now ~U[2026-10-24 10:00:00.000000Z]

  defp event(attrs \\ %{}) do
    Map.merge(
      %{
        id: "event",
        organization_id: "host",
        channel_id: nil,
        audience: "club",
        open_to_non_members: false,
        cancelled_at: nil,
        price_cents: 1000,
        currency: "EUR",
        starts_at: ~U[2026-10-24 18:00:00.000000Z],
        ends_at: ~U[2026-10-24 19:00:00.000000Z]
      },
      attrs
    )
  end

  describe "hosting as" do
    test "«Ως εγώ» is the default; a business is named by its organisation id" do
      assert HostPolicy.parse(nil) == :self
      assert HostPolicy.parse("self") == :self
      id = Ecto.UUID.generate()
      assert HostPolicy.parse(id) == {:business, id}
      assert HostPolicy.parse("nope") == {:error, :invalid_host}
      assert HostPolicy.parse(42) == {:error, :invalid_host}
    end

    test "a person's own event never belongs to a group" do
      assert HostPolicy.organiser_terms(%{channel_id: "g", audience: "group", title: "Run"}) ==
               %{audience: "club", title: "Run"}

      assert HostPolicy.organiser_terms(%{audience: "open"}) == %{audience: "open"}
    end

    test "creation is rate limited per day and by upcoming occurrences" do
      assert :ok = HostPolicy.creation_check(%{created_last_day: 4, upcoming: 0}, 1)

      assert {:error, :event_rate_limited} =
               HostPolicy.creation_check(%{created_last_day: 5, upcoming: 0}, 1)

      assert :ok = HostPolicy.creation_check(%{created_last_day: 0, upcoming: 20}, 10)

      assert {:error, :event_rate_limited} =
               HostPolicy.creation_check(%{created_last_day: 0, upcoming: 21}, 10)
    end

    test "the organiser organisation is named after the person" do
      assert HostPolicy.organiser_name("  Μαρία ") == "Μαρία"
      assert HostPolicy.organiser_name("x") == "Palee events"
      assert HostPolicy.organiser_name(nil) == "Palee events"
      assert HostPolicy.organiser?(%{provider_kind: "organiser"})
      refute HostPolicy.organiser?(%{provider_kind: "gym"})
    end
  end

  describe "co-hosting" do
    test "the host invites another box to an upcoming event that isn't a group's own" do
      assert :ok = CohostPolicy.invite_check(event(), "box", 0, nil, @now)
      assert :ok = CohostPolicy.invite_check(event(), "box", 0, "declined", @now)

      assert {:error, :cannot_cohost_own_event} =
               CohostPolicy.invite_check(event(), "host", 0, nil, @now)

      assert {:error, :event_cancelled} =
               CohostPolicy.invite_check(event(%{cancelled_at: @now}), "box", 0, nil, @now)

      assert {:error, :event_started} =
               CohostPolicy.invite_check(event(), "box", 0, nil, ~U[2026-10-24 19:00:00Z])

      assert {:error, :group_event} =
               CohostPolicy.invite_check(
                 event(%{channel_id: "g", audience: "group"}),
                 "box",
                 0,
                 nil,
                 @now
               )

      assert {:error, :already_invited} =
               CohostPolicy.invite_check(event(), "box", 1, "pending", @now)

      assert {:error, :cohost_limit_reached} =
               CohostPolicy.invite_check(event(), "box", 10, nil, @now)
    end

    test "a request is answered once; an accepted one can be withdrawn" do
      assert :ok = CohostPolicy.answer_check("pending", "accepted")
      assert :ok = CohostPolicy.answer_check("pending", "declined")
      assert :ok = CohostPolicy.answer_check("accepted", "removed")
      assert {:error, :not_pending} = CohostPolicy.answer_check("declined", "accepted")
      assert {:error, :not_pending} = CohostPolicy.answer_check("pending", "removed")

      request = %{status: "pending", cancelled_at: nil, ends_at: ~U[2026-10-24 19:00:00Z]}
      assert CohostPolicy.answerable?(request, @now)
      refute CohostPolicy.answerable?(%{request | status: "accepted"}, @now)
      refute CohostPolicy.answerable?(request, ~U[2026-10-25 10:00:00Z])
    end

    test "the co-host's trial offer goes once, after the event, to people who aren't its members" do
      facts = %{
        status: "accepted",
        cancelled_at: nil,
        trial_offer_sent_at: nil,
        ends_at: ~U[2026-10-24 09:00:00Z]
      }

      assert :ok = CohostPolicy.trial_offer_check(facts, @now)

      assert {:error, :not_found} =
               CohostPolicy.trial_offer_check(%{facts | status: "removed"}, @now)

      assert {:error, :trial_offer_already_sent} =
               CohostPolicy.trial_offer_check(%{facts | trial_offer_sent_at: @now}, @now)

      assert {:error, :event_not_over} =
               CohostPolicy.trial_offer_check(%{facts | ends_at: ~U[2026-10-24 11:00:00Z]}, @now)

      assert CohostPolicy.trial_offer_recipients(["a", "b", "a", "c"], ["b"]) == ["a", "c"]
    end
  end

  describe "the console's numbers" do
    defp attendee(attrs),
      do:
        Map.merge(
          %{
            status: "going",
            paid_at: nil,
            amount_cents: nil,
            refunded_at: nil,
            refund_cents: nil,
            checked_in_at: nil
          },
          attrs
        )

    test "income, refunds and what is still owed" do
      attendees = [
        attendee(%{paid_at: @now, amount_cents: 1000}),
        attendee(%{paid_at: @now, amount_cents: 1000, refunded_at: @now, refund_cents: 400}),
        attendee(%{}),
        attendee(%{status: "waitlisted"})
      ]

      assert %{
               paid_count: 2,
               paid_cents: 2000,
               refunded_count: 1,
               refunded_cents: 400,
               net_cents: 1600,
               outstanding_count: 1,
               outstanding_cents: 1000
             } = EventNumbers.finances(event(), attendees)

      assert %{outstanding_count: 0} =
               EventNumbers.finances(event(%{price_cents: 0}), [attendee(%{})])

      [eur] =
        EventNumbers.finance_totals([
          EventNumbers.finances(event(), attendees),
          EventNumbers.finances(event(), [attendee(%{paid_at: @now, amount_cents: 1000})])
        ])

      assert %{currency: "EUR", events: 2, paid_cents: 3000, net_cents: 2600} = eur

      assert [%{currency: "EUR"}, %{currency: "USD"}] =
               EventNumbers.finance_totals([
                 EventNumbers.finances(event(%{currency: "USD"}), []),
                 EventNumbers.finances(event(), [])
               ])
    end

    test "reach, response, attendance once over and conversion" do
      attendees = [
        attendee(%{checked_in_at: @now}),
        attendee(%{}),
        attendee(%{status: "waitlisted"}),
        attendee(%{status: "cancelled"})
      ]

      ahead = EventNumbers.analytics(event(), attendees, %{views: 30, viewers: 8}, @now)

      assert %{
               views: 30,
               viewers: 8,
               rsvps: 4,
               going: 2,
               waitlisted: 1,
               cancelled: 1,
               came: 1,
               attendance_rate: nil,
               conversion_rate: 50
             } = ahead

      over = EventNumbers.analytics(event(), attendees, %{}, ~U[2026-10-25 10:00:00Z])
      assert %{attendance_rate: 50, conversion_rate: nil, views: 0} = over

      assert %{events: 2, rsvps: 8, attendance_rate: 50, conversion_rate: 100} =
               EventNumbers.analytics_totals([ahead, over])
    end
  end
end
