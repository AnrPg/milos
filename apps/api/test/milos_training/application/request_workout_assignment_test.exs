defmodule MilosTraining.Application.RequestWorkoutAssignmentTest do
  use MilosTraining.DataCase, async: false

  alias MilosTraining.Application.RequestWorkoutAssignment
  alias MilosTraining.{Messaging, Notifications, Organizations}

  import MilosTraining.TestFixtures

  defp tenant_context_fixture(admin, name) do
    {:ok, organization} = Organizations.create_organization(%{name: name})

    {:ok, _membership} =
      Organizations.add_membership(%{
        organization_id: organization.id,
        user_id: admin.id,
        role: :owner,
        status: :active,
        joined_at: DateTime.utc_now()
      })

    {:ok, context} = Organizations.resolve_tenant_context(admin, organization.slug)
    context
  end

  test "creates an actionable admin notification instead of a chat message" do
    admin = admin_fixture()

    context =
      tenant_context_fixture(
        admin,
        "Request Assignment Gym #{System.unique_integer([:positive])}"
      )

    athlete = user_fixture(%{role: :athlete, nickname: "atlas_requester"})

    {:ok, _athlete_membership} =
      Organizations.add_membership(%{
        organization_id: context.organization_id,
        user_id: athlete.id,
        role: :athlete,
        status: :active,
        joined_at: DateTime.utc_now()
      })

    requested_for_iso = Date.utc_today() |> Date.add(1) |> Date.to_iso8601()

    assert {:ok, %{notified_admins: 1}} =
             RequestWorkoutAssignment.call(context, athlete, %{
               "requested_for" => requested_for_iso,
               "note" => "Please program a strength session."
             })

    assert Messaging.list_threads_for_user(admin.id) == []

    assert [notification] = Notifications.list_for_user(admin.id)
    assert notification.type == "workout_assignment_requested"

    assert notification.payload["url"] ==
             "/admin/coaching-assignments?date=#{requested_for_iso}"
  end
end
