defmodule MilosTraining.Application.SchedulingAnalyticsInstrumentationTest do
  @moduledoc "ADR-113: class slot, booking and attendance events."
  use MilosTraining.DataCase, async: false

  import MilosTraining.AnalyticsHelpers

  alias MilosTraining.Application.{
    AdminRecordAttendance,
    CreateScheduledSlot,
    DeleteScheduledSlot,
    ResolveBooking,
    SubmitBooking,
    TimeoutBooking,
    WithdrawBooking
  }

  alias MilosTraining.TestFixtures

  defp slot!(context, workout, class_type) do
    {:ok, slot} =
      CreateScheduledSlot.call(context, %{
        master_workout_id: workout.id,
        class_type_id: class_type.id,
        scheduled_at: DateTime.add(DateTime.utc_now() |> DateTime.truncate(:second), 7200),
        capacity: 10,
        auto_approve: false,
        booking_timeout_minutes: 60
      })

    slot
  end

  defp book!(organization, slot) do
    {member, member_context} = member_context(organization)
    {:ok, booking} = SubmitBooking.call(member_context, member, slot.id)
    {member, member_context, booking}
  end

  test "slot, booking lifecycle and attendance are recorded per tenant" do
    {organization, owner, context} = organization_fixture()
    workout = TestFixtures.workout_fixture(owner, %{tenant_context: context})
    class_type = TestFixtures.class_type_fixture(%{tenant_context: context})

    slot = slot!(context, workout, class_type)
    created = analytics_event!(organization.id, "class_slot_created")
    assert created.context_id == slot.id
    assert created.user_id == owner.id
    assert created.metadata["class_type_id"] == class_type.id
    assert created.metadata["capacity"] == 10
    assert created.metadata["auto_approve"] == false

    {approved_member, _ctx, approved} = book!(organization, slot)
    {_rejected_member, _ctx, rejected} = book!(organization, slot)
    {cancelling_member, cancelling_context, cancelled} = book!(organization, slot)
    {_late_member, _ctx, timed_out} = book!(organization, slot)

    requested = analytics_events(organization.id, "class_booking_requested")
    assert length(requested) == 4
    first = Enum.find(requested, &(&1.context_id == approved.id))
    assert first.user_id == approved_member.id
    assert first.metadata["scheduled_class_id"] == slot.id
    assert first.metadata["auto_approved"] == false

    assert {:ok, _, :resolved} =
             ResolveBooking.call(context, approved.id, %{"action" => "approve"})

    assert {:ok, _, :resolved} =
             ResolveBooking.call(context, rejected.id, %{"action" => "reject"})

    approved_event = analytics_event!(organization.id, "class_booking_approved")
    assert approved_event.context_id == approved.id
    assert approved_event.user_id == owner.id
    assert approved_event.metadata["member_id"] == approved_member.id
    assert analytics_event!(organization.id, "class_booking_rejected").context_id == rejected.id

    assert {:ok, _} = WithdrawBooking.call(cancelling_context, cancelling_member.id, cancelled.id)
    cancelled_event = analytics_event!(organization.id, "class_booking_cancelled")
    assert cancelled_event.context_id == cancelled.id
    assert cancelled_event.metadata["cancelled_by"] == "member"

    assert {:ok, _} = TimeoutBooking.call(organization.id, timed_out.id)
    assert analytics_event!(organization.id, "class_booking_timed_out").context_id == timed_out.id

    assert {:ok, attendance} =
             AdminRecordAttendance.call(context, slot.id, approved_member.id, owner.id, %{
               status: "attended"
             })

    attended = analytics_event!(organization.id, "class_attendance_recorded")
    assert attended.context_id == attendance.id
    assert attended.metadata["status"] == "attended"
    assert attended.metadata["member_id"] == approved_member.id
    assert attended.metadata["booking_id"] == approved.id

    empty_slot = slot!(context, workout, class_type)
    assert :ok = DeleteScheduledSlot.call(context, empty_slot.id)
    assert analytics_event!(organization.id, "class_slot_cancelled").context_id == empty_slot.id
  end
end
