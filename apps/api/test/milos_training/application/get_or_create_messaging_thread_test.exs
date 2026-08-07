defmodule MilosTraining.Application.GetOrCreateMessagingThreadTest do
  @moduledoc """
  Regression coverage for a cross-tenant IDOR found during the multi-tenancy
  audit doc sweep: authorization for assignment/class-slot threads used to key
  off the account's *global* `role`, and the auto-added staff participant list
  came from `Identity.list_by_role(:admin)` - every admin account on the
  entire platform, not just the thread's own organization. Both are fixed to
  key off organization membership instead.
  """
  use MilosTraining.DataCase, async: false

  alias MilosTraining.Application.GetOrCreateMessagingThread
  alias MilosTraining.Infrastructure.Tenancy.RepoContext
  alias MilosTraining.{Organizations, TestFixtures, Workouts}

  test "an admin of a different organization cannot open a thread for an assignment they have no membership in" do
    owner_a = TestFixtures.admin_fixture()
    owner_b = TestFixtures.admin_fixture()
    athlete_a = TestFixtures.user_fixture(%{role: :athlete})

    {:ok, org_a} = Organizations.create_organization(%{name: "Thread IDOR Gym A"})
    {:ok, org_b} = Organizations.create_organization(%{name: "Thread IDOR Gym B"})

    {:ok, _} =
      Organizations.add_membership(%{
        organization_id: org_a.id,
        user_id: owner_a.id,
        role: :owner,
        status: :active
      })

    {:ok, _} =
      Organizations.add_membership(%{
        organization_id: org_b.id,
        user_id: owner_b.id,
        role: :owner,
        status: :active
      })

    {:ok, _} =
      Organizations.add_membership(%{
        organization_id: org_a.id,
        user_id: athlete_a.id,
        role: :athlete,
        status: :active
      })

    assignment =
      RepoContext.run(%{organization_id: org_a.id, user_id: owner_a.id}, fn ->
        workout = TestFixtures.workout_fixture(owner_a)

        {:ok, assignment} =
          Workouts.assign_workout(%{
            master_workout_id: workout.id,
            athlete_ids: [athlete_a.id],
            scheduled_for: Date.utc_today()
          })

        assignment
      end)

    # Before the fix: owner_b's *global* :admin role alone granted access to
    # any organization's assignment thread.
    assert {:error, :forbidden} =
             GetOrCreateMessagingThread.call(owner_b, %{
               context_type: :assignment,
               context_id: assignment.id
             })

    thread =
      RepoContext.run(%{organization_id: org_a.id, user_id: owner_a.id}, fn ->
        assert {:ok, thread} =
                 GetOrCreateMessagingThread.call(owner_a, %{
                   context_type: :assignment,
                   context_id: assignment.id
                 })

        thread
      end)

    # Before the fix: every admin on the platform (owner_b included) was
    # auto-added as a thread participant via Identity.list_by_role(:admin).
    participant_ids = Enum.map(thread.participants, & &1.user_id)
    assert owner_a.id in participant_ids
    assert athlete_a.id in participant_ids
    refute owner_b.id in participant_ids
  end
end
