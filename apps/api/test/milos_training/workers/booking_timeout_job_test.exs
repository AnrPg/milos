defmodule MilosTraining.Workers.BookingTimeoutJobTest do
  use MilosTraining.DataCase, async: false
  use Oban.Testing, repo: MilosTraining.Repo

  alias MilosTraining.Application.SubmitBooking
  alias MilosTraining.Finance
  alias MilosTraining.Notifications
  alias MilosTraining.Scheduling
  alias MilosTraining.Workers.BookingTimeoutJob

  import MilosTraining.TestFixtures

  test "cancels pending booking, releases entitlement reservation, and sends alert" do
    admin = admin_fixture()
    member = user_fixture()
    workout = workout_fixture(admin)
    slot = slot_fixture(workout, %{auto_approve: false})

    second_slot =
      slot_fixture(workout, %{
        auto_approve: false,
        scheduled_at: DateTime.add(slot.scheduled_at, 3600)
      })

    provision_single_visit_package(member)

    assert {:ok, booking} = SubmitBooking.call(member.id, slot.id)

    assert {:error, :finance_allowance_exhausted, %{limit: 1, committed: 1}} =
             SubmitBooking.call(member.id, second_slot.id)

    assert :ok =
             perform_job(BookingTimeoutJob, %{
               "organization_id" => booking.organization_id,
               "booking_id" => booking.id
             })

    notifications = wait_for_notifications(admin.id)
    assert Enum.any?(notifications, &(&1.type == "booking_timeout"))

    assert %{status: :cancelled} = Scheduling.get_booking(booking.id)
    assert {:ok, %{status: :pending}} = SubmitBooking.call(member.id, second_slot.id)
  end

  test "no-ops when booking already resolved" do
    admin = admin_fixture()
    member = user_fixture()
    workout = workout_fixture(admin)
    slot = slot_fixture(workout)

    {:ok, booking} =
      Scheduling.submit_booking(member.id, slot.id, slot.booking_timeout_minutes)

    {:ok, _resolved} = Scheduling.approve_booking(booking.id, nil)

    assert :ok =
             perform_job(BookingTimeoutJob, %{
               "organization_id" => booking.organization_id,
               "booking_id" => booking.id
             })

    notifications = wait_for_notifications(admin.id)
    refute Enum.any?(notifications, &(&1.type == "booking_timeout"))
    assert %{status: :approved} = Scheduling.get_booking(booking.id)
  end

  defp provision_single_visit_package(member) do
    {:ok, _settings} =
      Finance.update_finance_settings(%{
        entitlement_enforcement_mode: "enforce_managed",
        entitlement_timezone: "Europe/Athens",
        payment_reminder_interval_days: 7
      })

    {:ok, package} =
      Finance.create_package(%{
        code: "timeout_visit_#{System.unique_integer([:positive])}",
        name: "Timeout visit",
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

    :ok
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
