defmodule MilosTraining.Application.AdminRecordAttendanceTest do
  use MilosTraining.DataCase

  alias MilosTraining.Application.AdminRecordAttendance
  alias MilosTraining.{Organizations, Scheduling}
  alias MilosTraining.TestFixtures

  setup do
    {:ok, legacy_organization} = Organizations.ensure_legacy_organization_for_migration()

    Repo.query!("SELECT set_config($1, $2, false)", [
      "app.organization_id",
      legacy_organization.id
    ])

    :ok
  end

  defp legacy_tenant_context(actor, role \\ nil) do
    {:ok, _membership} = Organizations.ensure_legacy_membership_for_migration(actor, role)

    {:ok, context} =
      Organizations.resolve_tenant_context(actor, Organizations.legacy_organization_slug())

    context
  end

  test "rejects attendance for a user without an approved booking for the class" do
    admin = TestFixtures.admin_fixture()
    member = TestFixtures.user_fixture()
    context = legacy_tenant_context(admin, :owner)
    legacy_tenant_context(member)
    workout = TestFixtures.workout_fixture(admin)
    slot = TestFixtures.slot_fixture(workout)

    assert {:error, :attendance_requires_approved_booking} =
             AdminRecordAttendance.call(context, slot.id, member.id, admin.id, %{
               status: "attended"
             })

    refute Scheduling.get_attendance_for_user_class(context, member.id, slot.id)
  end

  test "rejects attendance while the user's booking is still pending" do
    admin = TestFixtures.admin_fixture()
    member = TestFixtures.user_fixture()
    context = legacy_tenant_context(admin, :owner)
    legacy_tenant_context(member)
    workout = TestFixtures.workout_fixture(admin)
    slot = TestFixtures.slot_fixture(workout, %{auto_approve: false})

    assert {:ok, _booking} =
             Scheduling.submit_booking(context, member.id, slot.id, slot.booking_timeout_minutes)

    assert {:error, :attendance_requires_approved_booking} =
             AdminRecordAttendance.call(context, slot.id, member.id, admin.id, %{
               status: "attended"
             })
  end

  test "records attendance for a user with an approved booking for the class" do
    admin = TestFixtures.admin_fixture()
    member = TestFixtures.user_fixture()
    context = legacy_tenant_context(admin, :owner)
    legacy_tenant_context(member)
    workout = TestFixtures.workout_fixture(admin)
    slot = TestFixtures.slot_fixture(workout, %{auto_approve: true})

    assert {:ok, booking} = Scheduling.submit_auto_approved_booking(context, member.id, slot.id)

    assert {:ok, attendance} =
             AdminRecordAttendance.call(context, slot.id, member.id, admin.id, %{
               status: "attended",
               notes: "Checked in at front desk"
             })

    assert attendance.booking_id == booking.id
    assert attendance.status == "attended"
  end
end
