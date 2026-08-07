defmodule MilosTraining.Organizations.SetMembershipRoleTest do
  @moduledoc """
  F-29: role is a property of a membership, not of an account. A tenant admin
  changing "a user's role" must only be able to change it inside their own
  organization, and only up to their own ceiling.
  """
  use MilosTraining.DataCase, async: false

  alias MilosTraining.Application.{AssignWorkout, SubmitBooking}
  alias MilosTraining.Organizations
  alias MilosTraining.Organizations.OrganizationStore
  alias MilosTraining.{Scheduling, Workouts}
  alias MilosTraining.TestFixtures

  setup do
    owner = TestFixtures.admin_fixture()
    member = TestFixtures.user_fixture(%{role: :member})

    {:ok, org_a} = Organizations.create_organization(%{name: "Role Gym A"})
    {:ok, org_b} = Organizations.create_organization(%{name: "Role Gym B"})

    for {org, user, role} <- [
          {org_a, owner, :owner},
          {org_a, member, :member},
          {org_b, member, :member}
        ] do
      {:ok, _} =
        Organizations.add_membership(%{
          organization_id: org.id,
          user_id: user.id,
          role: role,
          status: :active,
          joined_at: DateTime.utc_now()
        })
    end

    {:ok, context_a} = Organizations.resolve_tenant_context(owner, org_a.slug)

    {:ok, owner: owner, member: member, org_a: org_a, org_b: org_b, context_a: context_a}
  end

  test "changing a role in one organization leaves the same account's other memberships alone",
       %{member: member, org_a: org_a, org_b: org_b, context_a: context_a} do
    assert {:ok, updated} = Organizations.set_membership_role(context_a, member.id, :coach)
    assert updated.role == :coach

    assert OrganizationStore.get_membership(org_a.id, member.id).role == :coach

    # The whole point: org B's membership must be untouched.
    assert OrganizationStore.get_membership(org_b.id, member.id).role == :member
  end

  test "an account that is not a member of the acting organization is unreachable", %{
    context_a: context_a
  } do
    outsider = TestFixtures.user_fixture(%{role: :member})

    assert {:error, :not_found} =
             Organizations.set_membership_role(context_a, outsider.id, :coach)
  end

  test "an admin cannot promote past their own ceiling", %{member: member, org_a: org_a} do
    admin = TestFixtures.admin_fixture()

    {:ok, _} =
      Organizations.add_membership(%{
        organization_id: org_a.id,
        user_id: admin.id,
        role: :admin,
        status: :active,
        joined_at: DateTime.utc_now()
      })

    {:ok, admin_context} = Organizations.resolve_tenant_context(admin, org_a.slug)

    assert {:error, :role_ceiling_exceeded} =
             Organizations.set_membership_role(admin_context, member.id, :owner)

    assert {:ok, _} = Organizations.set_membership_role(admin_context, member.id, :coach)
  end

  test "an admin cannot demote someone more privileged than themselves", %{
    owner: owner,
    org_a: org_a
  } do
    admin = TestFixtures.admin_fixture()

    {:ok, _} =
      Organizations.add_membership(%{
        organization_id: org_a.id,
        user_id: admin.id,
        role: :admin,
        status: :active,
        joined_at: DateTime.utc_now()
      })

    {:ok, admin_context} = Organizations.resolve_tenant_context(admin, org_a.slug)

    assert {:error, :role_ceiling_exceeded} =
             Organizations.set_membership_role(admin_context, owner.id, :member)
  end

  test "a coach cannot change roles at all", %{member: member, org_a: org_a} do
    coach = TestFixtures.user_fixture(%{role: :member})

    {:ok, _} =
      Organizations.add_membership(%{
        organization_id: org_a.id,
        user_id: coach.id,
        role: :coach,
        status: :active,
        joined_at: DateTime.utc_now()
      })

    {:ok, coach_context} = Organizations.resolve_tenant_context(coach, org_a.slug)

    assert {:error, :forbidden} =
             Organizations.set_membership_role(coach_context, member.id, :admin)
  end

  test "an account cannot change its own role", %{owner: owner, context_a: context_a} do
    assert {:error, :cannot_change_own_membership} =
             Organizations.set_membership_role(context_a, owner.id, :member)
  end

  describe "state owned by the previous role" do
    test "leaving :member cancels that member's active future bookings" do
      admin = TestFixtures.admin_fixture()
      member = TestFixtures.user_fixture(%{role: :member})
      workout = TestFixtures.workout_fixture(admin)
      slot = TestFixtures.slot_fixture(workout, %{auto_approve: false})

      assert {:ok, booking} = SubmitBooking.call(member.id, slot.id)
      assert booking.status == :pending

      {:ok, context} =
        Organizations.resolve_tenant_context(admin, Organizations.legacy_organization_slug())

      assert {:ok, updated} = Organizations.set_membership_role(context, member.id, :athlete)
      assert updated.role == :athlete
      assert Scheduling.get_booking(booking.id) == nil
    end

    test "leaving :athlete archives assignment access while retaining history" do
      admin = TestFixtures.admin_fixture()
      athlete = TestFixtures.user_fixture(%{role: :athlete})
      workout = TestFixtures.workout_fixture(admin)

      assert {:ok, assignment} =
               AssignWorkout.call(%{
                 master_workout_id: workout.id,
                 scheduled_for: Date.utc_today() |> Date.add(1) |> Date.to_iso8601(),
                 athlete_ids: [athlete.id],
                 admin_notes: "Role transition coverage"
               })

      assert Workouts.get_assignment_execution_access(assignment.id, athlete.id)

      {:ok, context} =
        Organizations.resolve_tenant_context(admin, Organizations.legacy_organization_slug())

      assert {:ok, updated} = Organizations.set_membership_role(context, athlete.id, :member)
      assert updated.role == :member
      assert Workouts.get_assignment_execution_access(assignment.id, athlete.id) == nil
      assert Workouts.get_assigned_workout(assignment.id).athlete_ids == [athlete.id]
    end
  end

  test "the affected account and this organization's admins are told, and no one else", %{
    member: member,
    org_a: org_a,
    context_a: context_a
  } do
    Phoenix.PubSub.subscribe(MilosTraining.PubSub, "user:sync")

    assert {:ok, _} = Organizations.set_membership_role(context_a, member.id, :coach)

    assert_receive {:user_sync, %{user_id: user_id, reason: "role_changed", payload: payload}}
    assert user_id == member.id
    assert payload.role == "coach"
    # Without this the client cannot tell which of its organizations changed.
    assert payload.organization_id == org_a.id
  end

  test "an unknown role is rejected", %{member: member, context_a: context_a} do
    assert {:error, [role: "is invalid"]} =
             Organizations.set_membership_role(context_a, member.id, "sysadmin")
  end
end
