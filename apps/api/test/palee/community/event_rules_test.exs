defmodule Palee.Community.EventRulesTest do
  @moduledoc "ADR-153: the pure rules of club events and weekly series."

  use ExUnit.Case, async: true

  alias Palee.Community.Domain.{EventPolicy, EventSeries}

  @now ~U[2026-10-24 10:00:00.000000Z]

  defp event(attrs \\ %{}) do
    Map.merge(
      %{
        capacity: 2,
        channel_id: nil,
        guest_pass_allowed: true,
        guests_per_member: 1,
        open_to_non_members: false,
        cancelled_at: nil,
        reminder_sent_at: nil,
        trial_offer_sent_at: nil,
        price_cents: 1500,
        starts_at: ~U[2026-10-24 18:00:00.000000Z],
        ends_at: ~U[2026-10-24 19:00:00.000000Z],
        location_id: nil,
        place_name: "Λόφος Φιλοπάππου",
        address: nil,
        latitude: nil,
        longitude: nil
      },
      attrs
    )
  end

  describe "who comes" do
    test "club members first, then anyone on an open event, then invited guests" do
      assert {:ok, "member"} = EventPolicy.source(%{club_member?: true, open?: false})
      assert {:ok, "open"} = EventPolicy.source(%{club_member?: false, open?: true})

      assert {:ok, {"guest", "inviter"}} =
               EventPolicy.source(%{club_member?: false, open?: false, invited_by: "inviter"})

      assert {:error, :not_invited} = EventPolicy.source(%{club_member?: false, open?: false})
    end

    test "guests need passes on, a going inviter and room in their allowance" do
      assert :ok = EventPolicy.guest_check(event(), "going", 0)
      assert {:error, :guest_limit_reached} = EventPolicy.guest_check(event(), "going", 1)
      assert {:error, :inviter_not_going} = EventPolicy.guest_check(event(), "waitlisted", 0)

      assert {:error, :guests_not_allowed} =
               EventPolicy.guest_check(event(%{guest_pass_allowed: false}), "going", 0)
    end

    test "no answers once cancelled or started" do
      assert :ok = EventPolicy.open_for_rsvp(event(), @now)

      assert {:error, :event_cancelled} =
               EventPolicy.open_for_rsvp(event(%{cancelled_at: @now}), @now)

      assert {:error, :event_started} =
               EventPolicy.open_for_rsvp(event(), ~U[2026-10-24 18:00:00.000000Z])
    end
  end

  describe "places" do
    test "a place while there is one, the waitlist after; no limit means always going" do
      assert "going" = EventPolicy.join_status(event(), 1)
      assert "waitlisted" = EventPolicy.join_status(event(), 2)
      assert "going" = EventPolicy.join_status(event(%{capacity: nil}), 500)
      assert 0 = EventPolicy.spots_left(event(), 3)
      assert nil == EventPolicy.spots_left(event(%{capacity: nil}), 3)
    end

    test "freed places go to the longest waiting, as many as are free" do
      waiting = [%{id: 1}, %{id: 2}, %{id: 3}]
      assert [%{id: 1}] = EventPolicy.promotions(event(), 1, waiting)
      assert [] = EventPolicy.promotions(event(), 2, waiting)
      assert [%{id: 1}, %{id: 2}] = EventPolicy.promotions(event(%{capacity: 4}), 2, waiting)
      assert ^waiting = EventPolicy.promotions(event(%{capacity: nil}), 9, waiting)
    end

    test "giving up a place within two hours of the start is a late cancel" do
      assert EventPolicy.late_cancel?("going", event(), ~U[2026-10-24 16:30:00.000000Z])
      refute EventPolicy.late_cancel?("going", event(), ~U[2026-10-24 15:59:00.000000Z])
      refute EventPolicy.late_cancel?("waitlisted", event(), ~U[2026-10-24 17:30:00.000000Z])
    end
  end

  describe "changes, reminders and the trial offer" do
    test "time and place changes are told apart" do
      assert [] = EventPolicy.notable_changes(event(), event(%{capacity: 10}))

      assert [:time] =
               EventPolicy.notable_changes(
                 event(),
                 event(%{starts_at: ~U[2026-10-24 18:30:00.000000Z]})
               )

      assert [:time, :place] =
               EventPolicy.notable_changes(
                 event(),
                 event(%{
                   ends_at: ~U[2026-10-24 20:00:00.000000Z],
                   place_name: "Πεδίον του Άρεως"
                 })
               )
    end

    test "the reminder is due within two hours of the start, once" do
      refute EventPolicy.reminder_due?(event(), @now)
      assert EventPolicy.reminder_due?(event(), ~U[2026-10-24 16:05:00.000000Z])

      refute EventPolicy.reminder_due?(
               event(%{reminder_sent_at: @now}),
               ~U[2026-10-24 16:05:00.000000Z]
             )

      refute EventPolicy.reminder_due?(
               event(%{cancelled_at: @now}),
               ~U[2026-10-24 16:05:00.000000Z]
             )
    end

    test "the trial offer goes once after the event, to non-members who came" do
      after_event = ~U[2026-10-24 20:00:00.000000Z]
      assert {:error, :event_not_over} = EventPolicy.trial_offer_check(event(), @now)
      assert :ok = EventPolicy.trial_offer_check(event(), after_event)

      assert {:error, :trial_offer_already_sent} =
               EventPolicy.trial_offer_check(
                 event(%{trial_offer_sent_at: after_event}),
                 after_event
               )

      came = %{user_id: "a", status: "going", checked_in_at: @now, trial_offered_at: nil}
      member = %{came | user_id: "m"}
      no_show = %{came | user_id: "b", checked_in_at: nil}
      offered = %{came | user_id: "c", trial_offered_at: @now}

      assert [%{user_id: "a"}] =
               EventPolicy.trial_offer_recipients([came, member, no_show, offered], ["m"])
    end

    test "payments are recorded once for held places on paid events" do
      assert :ok = EventPolicy.payment_check(event(), %{status: "going", paid_at: nil})

      assert {:error, :already_paid} =
               EventPolicy.payment_check(event(), %{status: "going", paid_at: @now})

      assert {:error, :not_going} =
               EventPolicy.payment_check(event(), %{status: "waitlisted", paid_at: nil})

      assert {:error, :event_is_free} = EventPolicy.payment_check(event(%{price_cents: 0}), %{})
    end

    test "numbers count no-shows only after the event" do
      rows = [
        %{
          status: "going",
          source: "member",
          checked_in_at: @now,
          paid_at: @now,
          late_cancel: false,
          converted_at: nil
        },
        %{
          status: "going",
          source: "guest",
          checked_in_at: nil,
          paid_at: nil,
          late_cancel: false,
          converted_at: nil
        },
        %{
          status: "cancelled",
          source: "open",
          checked_in_at: nil,
          paid_at: nil,
          late_cancel: true,
          converted_at: nil
        },
        %{
          status: "waitlisted",
          source: "open",
          checked_in_at: nil,
          paid_at: nil,
          late_cancel: false,
          converted_at: nil
        }
      ]

      assert %{going: 2, came: 1, no_shows: 0, guests: 1, paid: 1, late_cancels: 1, waitlisted: 1} =
               EventPolicy.stats(event(), rows, 0, @now)

      assert %{no_shows: 1, trial_requests: 3} =
               EventPolicy.stats(event(), rows, 3, ~U[2026-10-25 10:00:00.000000Z])
    end
  end

  describe "member groups" do
    @group %{
      id: "group",
      club_id: "club",
      kind: "member_group",
      status: "active",
      archived_at: nil
    }

    test "a group event is free and for the group, whatever was asked" do
      assert %{
               price_cents: 0,
               open_to_non_members: false,
               guest_pass_allowed: false,
               title: "Run"
             } =
               EventPolicy.group_terms(%{
                 title: "Run",
                 price_cents: 2000,
                 open_to_non_members: true,
                 guest_pass_allowed: true
               })
    end

    test "only an active, live group of the same club takes events" do
      assert :ok = EventPolicy.group_channel_check(@group, "club")
      assert {:error, :not_found} = EventPolicy.group_channel_check(@group, "other club")

      for changed <- [%{status: "pending"}, %{archived_at: @now}, %{kind: "custom"}] do
        assert {:error, :not_found} =
                 EventPolicy.group_channel_check(Map.merge(@group, changed), "club")
      end
    end

    test "the group's admins run its events; staff with manage_events run every event" do
      assert EventPolicy.group_admin?(@group, %{member?: true, role: "admin"})
      refute EventPolicy.group_admin?(@group, %{member?: true, role: "member"})
      refute EventPolicy.group_admin?(@group, %{member?: false, role: "admin"})

      refute EventPolicy.group_admin?(%{@group | status: "pending"}, %{
               member?: true,
               role: "admin"
             })

      refute EventPolicy.group_admin?(@group, nil)

      assert :ok = EventPolicy.manage_check(%{manage_events?: true, group_admin?: false}, nil)
      assert :ok = EventPolicy.manage_check(%{manage_events?: true, group_admin?: false}, "group")
      assert :ok = EventPolicy.manage_check(%{manage_events?: false, group_admin?: true}, "group")

      # Running a group gives no say over club events.
      assert {:error, :forbidden} =
               EventPolicy.manage_check(%{manage_events?: false, group_admin?: true}, nil)

      assert {:error, :forbidden} =
               EventPolicy.manage_check(%{manage_events?: false, group_admin?: false}, "group")
    end

    test "only the group's members see a group event and say they come" do
      group_event = event(%{channel_id: "group", price_cents: 0, guest_pass_allowed: false})
      club_member = %{club_member?: true, group_member?: false}
      group_member = %{club_member?: true, group_member?: true}

      assert EventPolicy.belongs?(event(), club_member)
      refute EventPolicy.belongs?(group_event, club_member)
      assert EventPolicy.belongs?(group_event, group_member)

      refute EventPolicy.visible?(group_event, %{belongs?: false})
      refute EventPolicy.visible?(group_event, %{belongs?: false, invited?: true})
      assert EventPolicy.visible?(group_event, %{belongs?: true})
      assert EventPolicy.visible?(group_event, %{belongs?: false, manager?: true})
      assert EventPolicy.visible?(event(%{open_to_non_members: true}), %{belongs?: false})

      refute EventPolicy.can_rsvp?(group_event, false, nil, @now)
      assert EventPolicy.can_rsvp?(group_event, true, nil, @now)
      # Somebody already on it can still give up the place after leaving the group.
      assert EventPolicy.can_rsvp?(group_event, false, "going", @now)
    end
  end

  describe "weekly series" do
    test "every week at the same local time, across a daylight-saving change" do
      # 19:00 Athens is 16:00 UTC in summer time and 17:00 UTC after 25 October.
      {:ok, weeks} =
        EventSeries.weekly(
          ~U[2026-10-20 16:00:00.000000Z],
          ~U[2026-10-20 17:00:00.000000Z],
          ~D[2026-11-03],
          "Europe/Athens"
        )

      assert [
               {~U[2026-10-20 16:00:00.000000Z], ~U[2026-10-20 17:00:00.000000Z]},
               {~U[2026-10-27 17:00:00.000000Z], ~U[2026-10-27 18:00:00.000000Z]},
               {~U[2026-11-03 17:00:00.000000Z], ~U[2026-11-03 18:00:00.000000Z]}
             ] = weeks
    end

    test "at most 26 occurrences, and never ending before it starts" do
      {:ok, weeks} =
        EventSeries.weekly(
          ~U[2026-10-20 16:00:00Z],
          ~U[2026-10-20 17:00:00Z],
          ~D[2028-01-01],
          "Etc/UTC"
        )

      assert length(weeks) == 26

      assert {:error, :invalid_repeat} =
               EventSeries.weekly(
                 ~U[2026-10-20 16:00:00Z],
                 ~U[2026-10-20 17:00:00Z],
                 ~D[2026-10-19],
                 "Etc/UTC"
               )
    end

    test "following occurrences move the way the edited one moved" do
      earlier = %{
        starts_at: ~U[2026-10-20 16:00:00.000000Z],
        ends_at: ~U[2026-10-20 17:00:00.000000Z]
      }

      # One day later, at 20:00 local, ninety minutes long.
      later = %{
        starts_at: ~U[2026-10-21 17:00:00.000000Z],
        ends_at: ~U[2026-10-21 18:30:00.000000Z]
      }

      next_week = %{
        starts_at: ~U[2026-10-27 17:00:00.000000Z],
        ends_at: ~U[2026-10-27 18:00:00.000000Z]
      }

      assert %{
               starts_at: ~U[2026-10-28 18:00:00.000000Z],
               ends_at: ~U[2026-10-28 19:30:00.000000Z]
             } =
               EventSeries.follow(next_week, earlier, later, "Europe/Athens")

      assert ^next_week = EventSeries.follow(next_week, earlier, earlier, "Europe/Athens")
    end
  end
end
