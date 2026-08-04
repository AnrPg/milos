defmodule MilosTraining.Workouts.TenantIsolationTest do
  use MilosTraining.DataCase, async: false

  alias MilosTraining.{Organizations.Organization, Repo, Workouts}
  alias MilosTraining.TestFixtures

  test "workout drafts are readable only through their organization context" do
    admin = TestFixtures.admin_fixture()
    organization_a = organization_fixture("workout-a")
    organization_b = organization_fixture("workout-b")

    context_a = %{organization_id: organization_a.id, user_id: admin.id}
    context_b = %{organization_id: organization_b.id, user_id: admin.id}

    assert {:ok, draft} = Workouts.create_draft(context_a, admin)
    assert [%{id: draft_id}] = Workouts.list_workouts(context_a)
    assert draft_id == draft.id
    assert Workouts.list_workouts(context_b) == []
    assert Workouts.get_workout_for_admin(context_b, draft.id) == nil
  end

  defp organization_fixture(suffix) do
    {:ok, organization} =
      %Organization{}
      |> Organization.changeset(%{
        name: "Workout tenant #{suffix}",
        slug: "workout-tenant-#{suffix}"
      })
      |> Repo.insert()

    organization
  end
end
