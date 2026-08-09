defmodule MilosTraining.AnalyticsTest do
  use MilosTraining.DataCase

  alias MilosTraining.Analytics
  alias MilosTraining.Application.MarkNotificationsRead
  alias MilosTraining.Notifications
  alias MilosTraining.Organizations
  alias MilosTraining.TestFixtures

  test "records analytics events and summarizes them by name" do
    user = TestFixtures.user_fixture()

    assert {:ok, event} =
             Analytics.record_event(%{
               event_name: "review_submitted",
               user_id: user.id,
               context_type: "review",
               metadata: %{target_type: "workout"}
             })

    assert event.event_name == "review_submitted"

    summary = Analytics.analytics_summary(%{"days" => "7"})
    assert summary.events.total >= 1
    assert summary.events.by_name["review_submitted"] >= 1
  end

  test "records push attempts and attendance facts for summary reads" do
    user = TestFixtures.user_fixture()
    admin = TestFixtures.admin_fixture()
    context = tenant_context_fixture(admin, "Attendance Analytics Gym")
    set_tenant_session!(context, admin.id)
    workout = TestFixtures.workout_fixture(admin)
    TestFixtures.class_type_fixture(%{tenant_context: context})
    slot = TestFixtures.slot_fixture(workout, %{tenant_context: context})

    assert {:ok, _attempt} =
             Analytics.record_push_attempt(%{
               user_id: user.id,
               endpoint_hash: "endpoint-hash",
               status: "sent"
             })

    assert {:ok, _attendance} =
             Analytics.record_attendance(context, %{
               scheduled_class_id: slot.id,
               user_id: user.id,
               status: "attended",
               marked_by_id: admin.id
             })

    summary = Analytics.analytics_summary(%{})
    assert summary.push_dispatch.by_status["sent"] >= 1
    assert summary.attendance.by_status["attended"] >= 1

    scheduling_attendance =
      MilosTraining.Scheduling.get_attendance_for_user_class(context, user.id, slot.id)

    assert scheduling_attendance.status == "attended"

    analytics_attendance = Analytics.get_attendance_for_user_class(context, user.id, slot.id)
    assert analytics_attendance.status == "attended"
  end

  test "records durable communication threads and messages for analytics" do
    user = TestFixtures.user_fixture()

    assert {:ok, message} =
             Analytics.record_communication_message(%{
               context_type: "general",
               sender_id: user.id,
               sender_role_snapshot: "member",
               recipient_role_snapshot: "admin",
               direction: "user_to_admin",
               body: "Can I scale tomorrow's class?"
             })

    assert message.thread_id
    assert message.direction == "user_to_admin"

    summary = Analytics.analytics_summary(%{})
    assert summary.communication.by_direction["user_to_admin"] >= 1
    assert summary.communication.by_channel["in_app"] >= 1
    assert summary.communication.threads_by_status["open"] >= 1
  end

  test "attendance booking must belong to the same user and class" do
    member = TestFixtures.user_fixture()
    other_member = TestFixtures.user_fixture()
    admin = TestFixtures.admin_fixture()
    context = tenant_context_fixture(admin, "Attendance Mismatch Gym")
    set_tenant_session!(context, admin.id)
    workout = TestFixtures.workout_fixture(admin)
    TestFixtures.class_type_fixture(%{tenant_context: context})
    slot = TestFixtures.slot_fixture(workout, %{tenant_context: context})

    assert {:ok, booking} =
             MilosTraining.Scheduling.submit_booking(
               context,
               member.id,
               slot.id,
               slot.booking_timeout_minutes
             )

    assert {:error, :attendance_booking_mismatch} =
             Analytics.record_attendance(context, %{
               booking_id: booking.id,
               scheduled_class_id: slot.id,
               user_id: other_member.id,
               status: "attended",
               marked_by_id: admin.id
             })
  end

  test "records analytics when notifications are bulk marked read" do
    user = TestFixtures.user_fixture()

    assert {:ok, _notification} =
             Notifications.create_notification(%{
               user_id: user.id,
               type: :workout_changed,
               payload: %{url: "/"}
             })

    assert MarkNotificationsRead.call(user.id) == 1

    summary = Analytics.analytics_summary(%{})
    assert summary.events.by_name["notification_read"] >= 1
  end

  defp tenant_context_fixture(owner, name) do
    {:ok, organization} = Organizations.create_organization(%{name: name})

    {:ok, _membership} =
      Organizations.add_membership(%{
        organization_id: organization.id,
        user_id: owner.id,
        role: :owner,
        status: :active,
        joined_at: DateTime.utc_now()
      })

    {:ok, context} = Organizations.resolve_tenant_context(owner, organization.slug)
    context
  end

  defp set_tenant_session!(context, user_id) do
    MilosTraining.Repo.query!("SELECT set_config($1, $2, false)", [
      "app.organization_id",
      context.organization_id
    ])

    MilosTraining.Repo.query!("SELECT set_config($1, $2, false)", ["app.user_id", user_id])
  end
end
