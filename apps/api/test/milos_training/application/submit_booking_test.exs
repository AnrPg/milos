defmodule MilosTraining.Application.SubmitBookingTest do
  use MilosTraining.DataCase, async: false
  use Oban.Testing, repo: MilosTraining.Repo

  alias MilosTraining.Application.SubmitBooking
  alias MilosTraining.Finance
  alias MilosTraining.Notifications
  alias MilosTraining.Workers.BookingTimeoutJob
  alias Oban.Testing

  import MilosTraining.TestFixtures

  setup do
    start_supervised!(
      {Oban, Keyword.put(Application.fetch_env!(:milos_training, Oban), :testing, :manual)}
    )

    previous_dispatcher = Application.get_env(:milos_training, :notification_dispatcher)

    on_exit(fn ->
      if previous_dispatcher do
        Application.put_env(:milos_training, :notification_dispatcher, previous_dispatcher)
      else
        Application.delete_env(:milos_training, :notification_dispatcher)
      end
    end)

    :ok
  end

  test "submitting a pending booking creates an admin notification and timeout job" do
    Testing.with_testing_mode(:manual, fn ->
      admin = admin_fixture()
      member = user_fixture()
      workout = workout_fixture(admin)
      slot = slot_fixture(workout, %{auto_approve: false})

      assert {:ok, booking} = SubmitBooking.call(member.id, slot.id)
      assert booking.status == :pending

      assert_enqueued(worker: BookingTimeoutJob, args: %{"booking_id" => booking.id})

      Oban.drain_queue(queue: :notifications, with_safety: false)

      notifications = wait_for_notifications(admin.id)
      assert Enum.any?(notifications, &(&1.type == "booking_pending"))
    end)
  end

  test "submitting an auto-approved booking resolves immediately" do
    Testing.with_testing_mode(:manual, fn ->
      admin = admin_fixture()
      member = user_fixture()
      workout = workout_fixture(admin)
      slot = slot_fixture(workout, %{auto_approve: true})

      assert {:ok, booking} = SubmitBooking.call(member.id, slot.id)
      assert booking.status == :approved

      Oban.drain_queue(queue: :notifications, with_safety: false)

      notifications = wait_for_notifications(member.id)
      assert Enum.any?(notifications, &(&1.type == "booking_approved"))
      refute_enqueued(worker: BookingTimeoutJob, args: %{"booking_id" => booking.id})
    end)
  end

  test "failed auto-approval leaves no pending booking or timeout job" do
    Testing.with_testing_mode(:manual, fn ->
      admin = admin_fixture()
      first_member = user_fixture()
      second_member = user_fixture()
      workout = workout_fixture(admin)
      slot = slot_fixture(workout, %{auto_approve: true, capacity: 1})

      assert {:ok, first_booking} = SubmitBooking.call(first_member.id, slot.id)
      assert first_booking.status == :approved

      assert {:error, :slot_full} = SubmitBooking.call(second_member.id, slot.id)

      refreshed_slot = MilosTraining.Scheduling.get_slot(slot.id)

      refute Enum.any?(
               refreshed_slot.bookings,
               &(&1.user_id == second_member.id and &1.status == :pending)
             )

      refute_enqueued(worker: BookingTimeoutJob, args: %{"booking_id" => first_booking.id})
    end)
  end

  test "inactive managed memberships cannot book classes" do
    admin = admin_fixture()
    member = user_fixture()
    workout = workout_fixture(admin)
    slot = slot_fixture(workout, %{auto_approve: true})

    assert {:ok, _membership} =
             Finance.upsert_membership(member.id, %{
               user_type_snapshot: "member",
               status: "paused",
               signup_source: "direct"
             })

    assert {:error, :finance_entitlement_inactive} =
             SubmitBooking.call(member.id, slot.id)
  end

  test "package visit quota is reserved across different slots and withdrawal restores it" do
    admin = admin_fixture()
    member = user_fixture()
    workout = workout_fixture(admin)
    first_slot = slot_fixture(workout, %{auto_approve: true})

    second_slot =
      slot_fixture(workout, %{
        auto_approve: true,
        scheduled_at: DateTime.add(first_slot.scheduled_at, 3600)
      })

    {:ok, _settings} =
      Finance.update_finance_settings(%{
        entitlement_enforcement_mode: "enforce_managed",
        entitlement_timezone: "Europe/Athens",
        payment_reminder_interval_days: 7
      })

    {:ok, package} =
      Finance.create_package(%{
        code: "one_visit_monthly",
        name: "One visit monthly",
        family: "limited-visits",
        billing_period: "monthly",
        params: %{
          "entitlement_version" => 1,
          "channels" => ["in_person"],
          "capabilities" => ["book_classes", "execute_class_workouts"],
          "allowances" => %{
            "class_visits" => %{"limit" => 1, "period" => "calendar_month"}
          }
        }
      })

    {:ok, membership} =
      Finance.upsert_membership(member.id, %{
        user_type_snapshot: "member",
        status: "active",
        signup_source: "direct"
      })

    {:ok, _subscription} =
      Finance.assign_package(membership.id, package.id, %{starts_on: Date.utc_today()})

    assert {:ok, booking} = SubmitBooking.call(member.id, first_slot.id)

    assert {:error, :finance_allowance_exhausted, %{limit: 1, committed: 1}} =
             SubmitBooking.call(member.id, second_slot.id)

    assert {:ok, _withdrawn} =
             MilosTraining.Application.WithdrawBooking.call(member.id, booking.id)

    assert {:ok, _second_booking} = SubmitBooking.call(member.id, second_slot.id)
  end

  test "returns the committed booking when notification dispatch fails" do
    Application.put_env(:milos_training, :notification_dispatcher, __MODULE__.FailingDispatcher)

    admin = admin_fixture()
    member = user_fixture()
    workout = workout_fixture(admin)
    slot = slot_fixture(workout, %{auto_approve: false})

    assert {:ok, booking} = SubmitBooking.call(member.id, slot.id)
    assert booking.status == :pending

    refreshed_slot = MilosTraining.Scheduling.get_slot(slot.id)
    assert Enum.any?(refreshed_slot.bookings, &(&1.id == booking.id))
  end

  defmodule FailingDispatcher do
    def dispatch_event(_event, _payload), do: {:error, :notification_store_down}
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
