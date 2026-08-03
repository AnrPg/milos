defmodule MilosTraining.Notifications.ConsolidatedDeliveryTest do
  use MilosTraining.DataCase, async: false

  alias MilosTraining.Notifications
  alias MilosTraining.TestFixtures

  @batch_at "2026-07-18T12:00:10Z"

  test "several workout assignments in one short batch create one athlete notification" do
    athlete = TestFixtures.user_fixture(%{role: :athlete})

    for assignment_id <- [Ecto.UUID.generate(), Ecto.UUID.generate()] do
      assert :ok =
               Notifications.process_event("workout_assigned", %{
                 "assignment_id" => assignment_id,
                 "athlete_ids" => [athlete.id],
                 "notification_batch_at" => @batch_at
               })
    end

    notifications = Notifications.list_for_user(athlete.id)
    assert [%{type: "workout_assigned", payload: payload}] = notifications
    assert payload["body"] =~ "one or more"
  end

  test "several booking approvals in one short batch create one member notification" do
    member = TestFixtures.user_fixture()

    for booking_id <- [Ecto.UUID.generate(), Ecto.UUID.generate()] do
      assert :ok =
               Notifications.process_event("booking_resolved", %{
                 "id" => booking_id,
                 "user_id" => member.id,
                 "scheduled_class_id" => Ecto.UUID.generate(),
                 "status" => "approved",
                 "notification_batch_at" => @batch_at
               })
    end

    notifications = Notifications.list_for_user(member.id)
    assert [%{type: "booking_approved", payload: payload}] = notifications
    assert payload["body"] =~ "one or more"
  end
end
