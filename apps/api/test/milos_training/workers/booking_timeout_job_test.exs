defmodule MilosTraining.Workers.BookingTimeoutJobTest do
  use MilosTraining.DataCase, async: false
  use Oban.Testing, repo: MilosTraining.Repo

  alias MilosTraining.Notifications
  alias MilosTraining.Scheduling
  alias MilosTraining.Workers.BookingTimeoutJob

  import MilosTraining.TestFixtures

  test "sends alert when booking still pending" do
    admin = admin_fixture()
    member = user_fixture()
    workout = workout_fixture(admin)
    slot = slot_fixture(workout)

    {:ok, booking} =
      Scheduling.submit_booking(member.id, slot.id, slot.booking_timeout_minutes)

    assert :ok = perform_job(BookingTimeoutJob, %{"booking_id" => booking.id})

    notifications = wait_for_notifications(admin.id)
    assert Enum.any?(notifications, &(&1.type == "booking_timeout"))
  end

  test "no-ops when booking already resolved" do
    admin = admin_fixture()
    member = user_fixture()
    workout = workout_fixture(admin)
    slot = slot_fixture(workout)

    {:ok, booking} =
      Scheduling.submit_booking(member.id, slot.id, slot.booking_timeout_minutes)

    {:ok, _resolved} = Scheduling.approve_booking(booking.id, nil)

    assert :ok = perform_job(BookingTimeoutJob, %{"booking_id" => booking.id})

    notifications = wait_for_notifications(admin.id)
    refute Enum.any?(notifications, &(&1.type == "booking_timeout"))
  end

  defp wait_for_notifications(user_id, attempts \\ 10)

  defp wait_for_notifications(user_id, attempts) when attempts > 0 do
    notifications = Notifications.list_for_user(user_id)

    if notifications == [] do
      Process.sleep(20)
      wait_for_notifications(user_id, attempts - 1)
    else
      notifications
    end
  end

  defp wait_for_notifications(user_id, 0), do: Notifications.list_for_user(user_id)
end
