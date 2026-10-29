defmodule Palee.Application.PlaceMemberInClassTest do
  @moduledoc "ADR-232: staff booking a member into a class or moving them."
  use Palee.DataCase, async: false

  alias Palee.Application.{GetClassPlacementOptions, PlaceMemberInClass, SubmitBooking}
  alias Palee.{Finance, Organizations, Scheduling}

  import Palee.TestFixtures

  setup do
    {:ok, organization} = Organizations.ensure_legacy_organization_for_migration()
    Repo.query!("SELECT set_config($1, $2, false)", ["app.organization_id", organization.id])

    admin = admin_fixture()
    admin_context = tenant_context(admin, :owner)
    workout = workout_fixture(admin)

    {:ok, _settings} =
      Finance.update_finance_settings(%{
        entitlement_enforcement_mode: "enforce_managed",
        entitlement_timezone: "Europe/Athens",
        payment_reminder_interval_days: 7
      })

    %{admin_context: admin_context, workout: workout}
  end

  defp tenant_context(actor, role \\ nil) do
    {:ok, _membership} = Organizations.ensure_legacy_membership_for_migration(actor, role)

    {:ok, context} =
      Organizations.resolve_tenant_context(actor, Organizations.legacy_organization_slug())

    context
  end

  # One visit and a 12-hour cancellation cutoff: a move that charged a late
  # cancellation, or needed a second visit, is refused.
  defp member_with_one_visit do
    {:ok, package} =
      Finance.create_package(%{
        name: "Package #{System.unique_integer([:positive])}",
        package_type: "class_pack",
        fields: %{
          "group_classes.visits" => %{"limit" => 1, "period" => "subscription_period"},
          "booking.cancellation_cutoff_hours" => 12
        }
      })

    user = user_fixture()
    context = tenant_context(user)

    {:ok, membership} =
      Finance.upsert_membership(user.id, %{
        user_type_snapshot: "member",
        status: "active",
        signup_source: "direct"
      })

    {:ok, _subscription} = Finance.assign_package(membership.id, package.id, %{})
    {user, context}
  end

  defp slot(workout, attrs), do: slot_fixture(workout, Map.merge(%{auto_approve: true}, attrs))

  defp hours_from_now(hours),
    do: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.add(hours * 3600, :second)

  defp status(booking_id) do
    case Repo.get(Palee.Scheduling.Booking, booking_id) do
      nil -> :withdrawn
      booking -> booking.status
    end
  end

  test "a move inside the cancellation cutoff reuses the visit instead of charging it", %{
    admin_context: admin_context,
    workout: workout
  } do
    {member, context} = member_with_one_visit()
    soon = slot(workout, %{scheduled_at: hours_from_now(2)})
    other = slot(workout, %{scheduled_at: hours_from_now(4), auto_approve: false})

    assert {:ok, booking} = SubmitBooking.call(context, member, soon.id)

    assert {:ok, %{booking: moved, previous_booking_id: previous_id}} =
             PlaceMemberInClass.call(admin_context, member.id, %{
               slot_id: other.id,
               from_booking_id: booking.id
             })

    assert previous_id == booking.id
    # Placed by staff: approved at once, although the class asks for approval.
    assert moved.status == :approved
    assert moved.scheduled_class_id == other.id
    assert status(booking.id) == :withdrawn

    # Still one visit committed in all: the move neither consumed the old one
    # as a late cancellation nor took a second.
    third = slot(workout, %{scheduled_at: hours_from_now(30)})

    assert {:error, :finance_allowance_exhausted, %{limit: 1, committed: 1}} =
             SubmitBooking.call(context, member, third.id)
  end

  test "a refused move leaves the old booking and its visit as they were", %{
    admin_context: admin_context,
    workout: workout
  } do
    {member, context} = member_with_one_visit()
    {other_member, other_context} = member_with_one_visit()
    soon = slot(workout, %{scheduled_at: hours_from_now(2)})
    full = slot(workout, %{scheduled_at: hours_from_now(4), capacity: 1})

    assert {:ok, booking} = SubmitBooking.call(context, member, soon.id)
    assert {:ok, _taken} = SubmitBooking.call(other_context, other_member, full.id)

    assert {:error, :slot_full} =
             PlaceMemberInClass.call(admin_context, member.id, %{
               slot_id: full.id,
               from_booking_id: booking.id
             })

    assert status(booking.id) == :approved

    third = slot(workout, %{scheduled_at: hours_from_now(30)})

    assert {:error, :finance_allowance_exhausted, %{limit: 1, committed: 1}} =
             SubmitBooking.call(context, member, third.id)
  end

  test "staff place a member before the member's own booking window opens", %{
    admin_context: admin_context,
    workout: workout
  } do
    {member, context} = member_with_one_visit()
    far = slot(workout, %{scheduled_at: hours_from_now(72)})

    {:ok, _settings} =
      Scheduling.update_settings(admin_context, %{default_booking_window_days: 1})

    assert {:error, :booking_window_closed, _details} =
             SubmitBooking.call(context, member, far.id)

    assert {:ok, %{booking: %{status: :approved}, previous_booking_id: nil}} =
             PlaceMemberInClass.call(admin_context, member.id, %{slot_id: far.id})
  end

  test "the options list the member's bookings and say why a class cannot take them", %{
    admin_context: admin_context,
    workout: workout
  } do
    {member, context} = member_with_one_visit()
    {other_member, other_context} = member_with_one_visit()
    booked = slot(workout, %{scheduled_at: hours_from_now(2)})
    open = slot(workout, %{scheduled_at: hours_from_now(4)})
    full = slot(workout, %{scheduled_at: hours_from_now(6), capacity: 1})

    assert {:ok, booking} = SubmitBooking.call(context, member, booked.id)
    assert {:ok, _taken} = SubmitBooking.call(other_context, other_member, full.id)

    assert {:ok, options} = GetClassPlacementOptions.call(admin_context, member.id)

    assert options.timezone == Organizations.organization_timezone(admin_context.organization_id)
    assert [%{booking_id: booking_id, slot_id: booked_id, status: :approved}] = options.bookings
    assert {booking_id, booked_id} == {booking.id, booked.id}

    reasons = Map.new(options.classes, &{&1.slot_id, &1.blocked_reason})
    # The member's one visit is held by their booking: only a move can take them.
    assert reasons[open.id] == "finance_allowance_exhausted"
    assert reasons[full.id] == "slot_full"
    refute Map.has_key?(reasons, booked.id)

    # Checking the package reserved nothing.
    {fresh, _fresh_context} = member_with_one_visit()

    assert {:ok, %{bookings: [], classes: classes}} =
             GetClassPlacementOptions.call(admin_context, fresh.id)

    reasons = Map.new(classes, &{&1.slot_id, &1.blocked_reason})
    assert reasons[open.id] == nil
    assert reasons[booked.id] == nil
    assert {:ok, _options} = GetClassPlacementOptions.call(admin_context, fresh.id)

    assert {:ok, %{booking: %{status: :approved}}} =
             PlaceMemberInClass.call(admin_context, fresh.id, %{slot_id: open.id})
  end

  test "only members of the box are placed or listed", %{admin_context: admin_context} do
    athlete = user_fixture(%{role: :athlete})
    _context = tenant_context(athlete, :athlete)

    assert {:error, :class_placement_requires_member} =
             GetClassPlacementOptions.call(admin_context, athlete.id)
  end
end
