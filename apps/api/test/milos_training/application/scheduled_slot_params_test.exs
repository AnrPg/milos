defmodule MilosTraining.Application.ScheduledSlotParamsTest do
  use MilosTraining.DataCase, async: false

  alias MilosTraining.Application.{CreateScheduledSlot, UpdateScheduledSlot}
  alias MilosTraining.Organizations

  import MilosTraining.TestFixtures

  setup do
    owner = admin_fixture()
    context = tenant_context_fixture(owner)

    Repo.query!("SELECT set_config($1, $2, false)", [
      "app.organization_id",
      context.organization_id
    ])

    Repo.query!("SELECT set_config($1, $2, false)", ["app.user_id", owner.id])

    %{tenant_context: context, tenant_owner: owner}
  end

  defp tenant_context_fixture(owner) do
    {:ok, organization} =
      Organizations.create_organization(%{
        name: "Scheduled Slot Params Gym #{System.unique_integer([:positive])}"
      })

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

  test "create handles OpenAPI-cast atom-key params with an explicit class type", %{
    tenant_context: context,
    tenant_owner: admin
  } do
    workout = workout_fixture(admin, %{type: :crossfit})
    class_type = class_type_fixture(%{tenant_context: context})

    params = %{
      master_workout_id: workout.id,
      class_type_id: class_type.id,
      scheduled_at: DateTime.add(DateTime.utc_now() |> DateTime.truncate(:second), 3600, :second),
      capacity: 12,
      auto_approve: false,
      booking_timeout_minutes: 60
    }

    assert {:ok, slot} = CreateScheduledSlot.call(context, params)
    assert slot.class_type_id == class_type.id
  end

  test "update handles OpenAPI-cast atom-key params with an explicit class type", %{
    tenant_context: context,
    tenant_owner: admin
  } do
    workout = workout_fixture(admin, %{type: :crossfit})
    initial_class_type = class_type_fixture(%{tenant_context: context})

    slot =
      slot_fixture(workout, %{tenant_context: context, class_type_id: initial_class_type.id})

    class_type = class_type_fixture(%{tenant_context: context})

    params = %{
      master_workout_id: workout.id,
      class_type_id: class_type.id,
      scheduled_at: DateTime.add(DateTime.utc_now() |> DateTime.truncate(:second), 7200, :second),
      capacity: 8,
      auto_approve: true,
      booking_timeout_minutes: 30
    }

    assert {:ok, updated_slot} = UpdateScheduledSlot.call(context, slot.id, params)
    assert updated_slot.class_type_id == class_type.id
    assert updated_slot.capacity == 8
  end
end
