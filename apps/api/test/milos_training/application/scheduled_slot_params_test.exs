defmodule MilosTraining.Application.ScheduledSlotParamsTest do
  use MilosTraining.DataCase, async: false

  alias MilosTraining.Application.{CreateScheduledSlot, UpdateScheduledSlot}

  import MilosTraining.TestFixtures

  test "create handles OpenAPI-cast atom-key params without mixing training_type keys" do
    admin = admin_fixture()
    workout = workout_fixture(admin, %{type: :crossfit})

    params = %{
      master_workout_id: workout.id,
      scheduled_at: DateTime.add(DateTime.utc_now() |> DateTime.truncate(:second), 3600, :second),
      capacity: 12,
      auto_approve: false,
      booking_timeout_minutes: 60
    }

    assert {:ok, slot} = CreateScheduledSlot.call(params)
    assert slot.training_type == "crossfit"
  end

  test "update handles OpenAPI-cast atom-key params without mixing training_type keys" do
    admin = admin_fixture()
    workout = workout_fixture(admin, %{type: :crossfit})
    slot = slot_fixture(workout)

    params = %{
      master_workout_id: workout.id,
      scheduled_at: DateTime.add(DateTime.utc_now() |> DateTime.truncate(:second), 7200, :second),
      capacity: 8,
      auto_approve: true,
      booking_timeout_minutes: 30
    }

    assert {:ok, updated_slot} = UpdateScheduledSlot.call(slot.id, params)
    assert updated_slot.training_type == "crossfit"
    assert updated_slot.capacity == 8
  end
end
