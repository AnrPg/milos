defmodule MilosTraining.Application.AdminRecordAttendanceTest do
  use MilosTraining.DataCase

  alias MilosTraining.Application.AdminRecordAttendance
  alias MilosTraining.Scheduling
  alias MilosTraining.TestFixtures

  test "rejects attendance for a user without an approved booking for the class" do
    admin = TestFixtures.admin_fixture()
    member = TestFixtures.user_fixture()
    workout = TestFixtures.workout_fixture(admin)
    slot = TestFixtures.slot_fixture(workout)

    assert {:error, :attendance_requires_approved_booking} =
             AdminRecordAttendance.call(slot.id, member.id, admin.id, %{status: "attended"})

    refute Scheduling.get_attendance_for_user_class(member.id, slot.id)
  end

  test "rejects attendance while the user's booking is still pending" do
    admin = TestFixtures.admin_fixture()
    member = TestFixtures.user_fixture()
    workout = TestFixtures.workout_fixture(admin)
    slot = TestFixtures.slot_fixture(workout, %{auto_approve: false})

    assert {:ok, _booking} =
             Scheduling.submit_booking(member.id, slot.id, slot.booking_timeout_minutes)

    assert {:error, :attendance_requires_approved_booking} =
             AdminRecordAttendance.call(slot.id, member.id, admin.id, %{status: "attended"})
  end

  test "records attendance for a user with an approved booking for the class" do
    admin = TestFixtures.admin_fixture()
    member = TestFixtures.user_fixture()
    workout = TestFixtures.workout_fixture(admin)
    slot = TestFixtures.slot_fixture(workout, %{auto_approve: true})

    assert {:ok, booking} = Scheduling.submit_auto_approved_booking(member.id, slot.id)

    assert {:ok, attendance} =
             AdminRecordAttendance.call(slot.id, member.id, admin.id, %{
               status: "attended",
               notes: "Checked in at front desk"
             })

    assert attendance.booking_id == booking.id
    assert attendance.status == "attended"
  end
end
