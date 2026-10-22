defmodule Palee.Application.PhaseBBookingTest do
  use Palee.DataCase, async: false
  use Oban.Testing, repo: Palee.Repo

  alias Palee.Application.{
    AdminRecordAttendance,
    JoinClassWaitlist,
    SubmitBooking,
    SubmitGuestBooking,
    WithdrawBooking
  }

  alias Palee.{Finance, Notifications, Organizations, Scheduling}
  alias Palee.Workers.PackageExpiryReminderJob
  alias Oban.Testing

  import Palee.TestFixtures

  setup do
    start_supervised!(
      {Oban, Keyword.put(Application.fetch_env!(:palee, Oban), :testing, :manual)}
    )

    {:ok, organization} = Organizations.ensure_legacy_organization_for_migration()

    Repo.query!("SELECT set_config($1, $2, false)", ["app.organization_id", organization.id])

    admin = admin_fixture()
    admin_context = tenant_context(admin, :owner)
    workout = workout_fixture(admin)

    %{admin: admin, admin_context: admin_context, workout: workout}
  end

  defp tenant_context(actor, role \\ nil) do
    {:ok, _membership} = Organizations.ensure_legacy_membership_for_migration(actor, role)

    {:ok, context} =
      Organizations.resolve_tenant_context(actor, Organizations.legacy_organization_slug())

    context
  end

  defp enforce! do
    {:ok, _settings} =
      Finance.update_finance_settings(%{
        entitlement_enforcement_mode: "enforce_managed",
        entitlement_timezone: "Europe/Athens",
        payment_reminder_interval_days: 7
      })
  end

  defp member_with(package_type, fields, assign \\ %{}) do
    {:ok, package} =
      Finance.create_package(%{
        name: "Package #{System.unique_integer([:positive])}",
        package_type: package_type,
        fields: fields
      })

    user = user_fixture()
    context = tenant_context(user)

    {:ok, membership} =
      Finance.upsert_membership(user.id, %{
        user_type_snapshot: "member",
        status: "active",
        signup_source: "direct"
      })

    {:ok, _subscription} = Finance.assign_package(membership.id, package.id, assign)
    {user, context}
  end

  defp class_type(context, attrs) do
    unique = System.unique_integer([:positive])

    {:ok, class_type} =
      Scheduling.create_class_type(
        context,
        Map.merge(%{name: "Type #{unique}", slug: "type-#{unique}", sort_order: unique}, attrs)
      )

    class_type
  end

  defp slot(workout, attrs) do
    slot_fixture(workout, Map.merge(%{auto_approve: true}, attrs))
  end

  defp hours_from_now(hours),
    do: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.add(hours * 3600, :second)

  test "a class type's credit cost is consumed per booking", %{
    admin_context: admin_context,
    workout: workout
  } do
    enforce!()

    heavy = class_type(admin_context, %{credit_cost: 3})

    {member, context} =
      member_with("class_pack", %{
        "group_classes.visits" => %{"limit" => 4, "period" => "subscription_period"}
      })

    first = slot(workout, %{class_type_id: heavy.id})
    second = slot(workout, %{class_type_id: heavy.id, scheduled_at: hours_from_now(2)})

    assert {:ok, %{status: :approved}} = SubmitBooking.call(context, member, first.id)

    assert {:error, :finance_allowance_exhausted, %{limit: 4, committed: 3}} =
             SubmitBooking.call(context, member, second.id)
  end

  test "a class after the gym's midnight belongs to that gym day (ADR-176)", %{
    workout: workout
  } do
    # Every booking needs a package, and none covers a day past its last
    # (no grace slack).
    {:ok, _settings} =
      Finance.update_finance_settings(%{
        entitlement_enforcement_mode: "enforce_all",
        subscription_grace_days: 0
      })

    zone = Palee.TimeZones.ZonedTime.default_zone()
    last_day = Date.add(gym_today(), 3)

    {member, context} =
      member_with(
        "class_pack",
        %{"group_classes.visits" => %{"limit" => 2, "period" => "subscription_period"}},
        %{"ends_on" => Date.to_iso8601(last_day)}
      )

    at = fn date, time -> date |> DateTime.new!(time, zone) |> DateTime.shift_zone!("Etc/UTC") end

    # Late on the last day is covered; 00:30 the next gym day is not, although
    # it is still the last day in UTC east of Greenwich.
    assert {:ok, %{status: :approved}} =
             SubmitBooking.call(
               context,
               member,
               slot(workout, %{scheduled_at: at.(last_day, ~T[23:30:00])}).id
             )

    assert {:error, :finance_entitlement_plan_missing} =
             SubmitBooking.call(
               context,
               member,
               slot(workout, %{scheduled_at: at.(Date.add(last_day, 1), ~T[00:30:00])}).id
             )
  end

  test "events are booked on event visits and need the events perk", %{
    admin_context: admin_context,
    workout: workout
  } do
    enforce!()

    event_type = class_type(admin_context, %{kind: "event"})
    event = slot(workout, %{class_type_id: event_type.id})

    {without_events, without_context} = member_with("membership", %{})

    assert {:error, _reason, _details} =
             SubmitBooking.call(without_context, without_events, event.id)

    {member, context} =
      member_with("membership", %{
        "perks.events" => true,
        "perks.event_visits" => %{"limit" => 1, "period" => "calendar_month"}
      })

    assert {:ok, booking} = SubmitBooking.call(context, member, event.id)
    assert booking.entitlement_allowance == "event_visits"

    second = slot(workout, %{class_type_id: event_type.id, scheduled_at: hours_from_now(2)})

    assert {:error, :finance_allowance_exhausted, %{limit: 1}} =
             SubmitBooking.call(context, member, second.id)
  end

  test "the package booking window and the gym default limit how far ahead members book", %{
    admin_context: admin_context,
    workout: workout
  } do
    far = slot(workout, %{scheduled_at: hours_from_now(72)})
    near = slot(workout, %{scheduled_at: hours_from_now(2)})

    {:ok, _settings} =
      Scheduling.update_settings(admin_context, %{default_booking_window_days: 1})

    guest_member = user_fixture()
    guest_context = tenant_context(guest_member)

    assert {:error, :booking_window_closed, %{opens_at: opens_at}} =
             SubmitBooking.call(guest_context, guest_member, far.id)

    assert DateTime.compare(opens_at, far.scheduled_at) == :lt
    assert {:ok, _booking} = SubmitBooking.call(guest_context, guest_member, near.id)

    enforce!()
    {member, context} = member_with("membership", %{"booking.window_days" => 7})
    assert {:ok, _booking} = SubmitBooking.call(context, member, far.id)
  end

  test "withdrawing inside the cancellation cutoff consumes the visit", %{workout: workout} do
    enforce!()

    {member, context} =
      member_with("class_pack", %{
        "group_classes.visits" => %{"limit" => 2, "period" => "subscription_period"},
        "booking.cancellation_cutoff_hours" => 12
      })

    soon = slot(workout, %{scheduled_at: hours_from_now(2)})
    later = slot(workout, %{scheduled_at: hours_from_now(48)})

    assert {:ok, soon_booking} = SubmitBooking.call(context, member, soon.id)

    assert {:ok, %{late_cancellation: true}} =
             WithdrawBooking.call(context, member.id, soon_booking.id)

    assert {:ok, later_booking} = SubmitBooking.call(context, member, later.id)

    assert {:ok, %{late_cancellation: false}} =
             WithdrawBooking.call(context, member.id, later_booking.id)

    # The late cancellation kept one visit; the on-time withdrawal returned its own.
    assert {:ok, _} = SubmitBooking.call(context, member, later.id)

    third = slot(workout, %{scheduled_at: hours_from_now(50)})

    assert {:error, :finance_allowance_exhausted, %{limit: 2, committed: 2}} =
             SubmitBooking.call(context, member, third.id)
  end

  test "a package that waives no-shows returns the visit", %{
    admin: admin,
    admin_context: admin_context,
    workout: workout
  } do
    enforce!()

    {member, context} =
      member_with("class_pack", %{
        "group_classes.visits" => %{"limit" => 1, "period" => "subscription_period"},
        "booking.no_show_penalty_waived" => true
      })

    first = slot(workout, %{})
    assert {:ok, _booking} = SubmitBooking.call(context, member, first.id)

    assert {:ok, %{status: "no_show"}} =
             AdminRecordAttendance.call(admin_context, first.id, member.id, admin.id, %{
               "status" => "no_show"
             })

    second = slot(workout, %{scheduled_at: hours_from_now(2)})
    assert {:ok, _booking} = SubmitBooking.call(context, member, second.id)
  end

  test "full classes take a waitlist that is promoted in priority order when a spot frees", %{
    workout: workout
  } do
    Testing.with_testing_mode(:manual, fn ->
      enforce!()
      full = slot(workout, %{capacity: 1})

      {booked, booked_context} = member_with("membership", %{})
      {normal, normal_context} = member_with("membership", %{})

      {priority, priority_context} =
        member_with("membership", %{"booking.waitlist_priority" => "high"})

      assert {:error, :slot_not_full} = JoinClassWaitlist.call(booked_context, booked, full.id)
      assert {:ok, booking} = SubmitBooking.call(booked_context, booked, full.id)
      assert {:error, :slot_full} = SubmitBooking.call(normal_context, normal, full.id)

      assert {:ok, %{status: :waitlisted}} =
               JoinClassWaitlist.call(normal_context, normal, full.id)

      assert {:ok, %{status: :waitlisted, waitlist_priority: 1}} =
               JoinClassWaitlist.call(priority_context, priority, full.id)

      assert {:error, :already_booked} = JoinClassWaitlist.call(normal_context, normal, full.id)

      assert {:ok, _withdrawn} = WithdrawBooking.call(booked_context, booked.id, booking.id)

      slot = Scheduling.get_slot(booked_context, full.id)
      statuses = Map.new(slot.bookings, &{&1.user_id, &1.status})
      assert statuses[priority.id] == :approved
      assert statuses[normal.id] == :waitlisted

      Oban.drain_queue(queue: :notifications, with_safety: false)

      promoted =
        priority.id
        |> Notifications.list_for_user()
        |> Enum.find(&(&1.type == "booking_waitlist_promoted"))

      assert promoted.payload["scheduled_class_id"] == full.id

      [entry] = Scheduling.list_waitlist(normal_context, full.id)

      assert {:ok, %{status: :waitlisted}} =
               WithdrawBooking.call(normal_context, normal.id, entry.id)

      assert Scheduling.list_waitlist(normal_context, full.id) == []
    end)
  end

  test "members book one named guest per class on guest passes", %{workout: workout} do
    enforce!()

    {member, context} =
      member_with("membership", %{
        "perks.guest_passes" => %{"limit" => 1, "period" => "calendar_month"}
      })

    first = slot(workout, %{})
    second = slot(workout, %{scheduled_at: hours_from_now(2)})

    assert {:error, :invalid_guest_name} = SubmitGuestBooking.call(context, member, first.id, " ")

    assert {:ok, own} = SubmitBooking.call(context, member, first.id)
    assert {:ok, guest} = SubmitGuestBooking.call(context, member, first.id, "Anna")
    assert guest.guest_name == "Anna"
    assert guest.entitlement_allowance == "guest_passes"

    assert {:error, :guest_already_booked} =
             SubmitGuestBooking.call(context, member, first.id, "Nikos")

    assert {:error, :finance_allowance_exhausted, %{limit: 1}} =
             SubmitGuestBooking.call(context, member, second.id, "Nikos")

    # Withdrawing the guest returns the pass and leaves the member's own booking.
    assert {:ok, _} = WithdrawBooking.call(context, member.id, guest.id)
    assert Scheduling.get_booking(context, own.id).status == :approved
    assert {:ok, _} = SubmitGuestBooking.call(context, member, second.id, "Nikos")

    {no_guests, no_guests_context} = member_with("membership", %{})

    assert {:error, _reason, _details} =
             SubmitGuestBooking.call(no_guests_context, no_guests, second.id, "Eleni")
  end

  test "members are reminded before their package ends" do
    Testing.with_testing_mode(:manual, fn ->
      today = gym_today()
      {member, _context} = member_with("trial", %{}, %{starts_on: Date.add(today, -4)})

      assert :ok = PackageExpiryReminderJob.perform(%Oban.Job{args: %{}})
      Oban.drain_queue(queue: :notifications, with_safety: false)

      expiring =
        member.id
        |> Notifications.list_for_user()
        |> Enum.find(&(&1.type == "package_expiring"))

      assert expiring.payload["days"] == 2
    end)
  end
end
