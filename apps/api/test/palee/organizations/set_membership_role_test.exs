defmodule Palee.Organizations.SetMembershipRoleTest do
  @moduledoc """
  F-29: role is a property of a membership, not of an account. A tenant admin
  changing "a user's role" must only be able to change it inside their own
  organization, and only up to their own ceiling.
  """
  use Palee.DataCase, async: false

  alias Palee.Application.{AssignWorkout, SubmitBooking}
  alias Palee.Organizations
  alias Palee.Organizations.OrganizationStore
  alias Palee.{Scheduling, Workouts}
  alias Palee.TestFixtures

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

  test "a coach cannot change roles (ADR-099)", %{member: member, org_a: org_a} do
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
             Organizations.set_membership_role(coach_context, member.id, :owner)

    assert {:error, :forbidden} =
             Organizations.set_membership_role(coach_context, member.id, :athlete)
  end

  test "an account never changes its own top role", %{owner: owner, context_a: context_a} do
    assert {:error, :own_top_role_locked} =
             Organizations.set_membership_role(context_a, owner.id, :member)

    assert {:error, :own_top_role_locked} =
             Organizations.set_membership_roles(context_a, owner.id, ["coach"])
  end

  describe "the hierarchy (ADR-219)" do
    defp join_as(org, user, roles) do
      {:ok, _} =
        Organizations.add_membership(%{
          organization_id: org.id,
          user_id: user.id,
          role: hd(roles),
          roles: roles,
          status: :active,
          joined_at: DateTime.utc_now()
        })

      {:ok, context} = Organizations.resolve_tenant_context(user, org.slug)
      context
    end

    test "an owner adds and drops lower roles on themselves and stays owner",
         %{owner: owner, org_a: org_a, context_a: context_a} do
      assert {:ok, membership} =
               Organizations.set_membership_roles(context_a, owner.id, ["owner", "coach"])

      assert membership.roles == [:owner, :coach]
      assert membership.role == :owner

      assert {:ok, %{roles: [:owner]}} =
               Organizations.set_membership_roles(context_a, owner.id, ["owner"])

      assert OrganizationStore.get_membership(org_a.id, owner.id).roles == [:owner]
    end

    test "an admin adds a staff role to themselves but never an owner role",
         %{org_a: org_a} do
      admin = TestFixtures.admin_fixture()
      context = join_as(org_a, admin, [:admin])

      assert {:ok, %{roles: [:admin, :coach, :member]}} =
               Organizations.set_membership_roles(context, admin.id, ["admin", "coach", "member"])

      assert {:error, :own_top_role_locked} =
               Organizations.set_membership_roles(context, admin.id, ["owner", "admin"])

      assert {:error, :own_top_role_locked} =
               Organizations.set_membership_roles(context, admin.id, ["coach"])
    end

    test "a coach adds a client role to themselves without the right to grant staff roles",
         %{org_a: org_a} do
      coach = TestFixtures.user_fixture(%{role: :member})
      context = join_as(org_a, coach, [:coach])

      assert {:ok, %{roles: [:coach, :member]}} =
               Organizations.set_membership_roles(context, coach.id, ["coach", "member"])

      assert {:error, :own_top_role_locked} =
               Organizations.set_membership_roles(context, coach.id, ["coach", "front_desk"])
    end

    test "an admin cannot touch a fellow admin or an owner, even their lower roles",
         %{owner: owner, org_a: org_a} do
      admin = TestFixtures.admin_fixture()
      context = join_as(org_a, admin, [:admin])
      other_admin = TestFixtures.admin_fixture()
      join_as(org_a, other_admin, [:admin])

      assert {:error, :role_ceiling_exceeded} =
               Organizations.set_membership_roles(context, other_admin.id, ["admin", "coach"])

      assert {:error, :role_ceiling_exceeded} =
               Organizations.set_membership_roles(context, owner.id, ["owner", "member"])

      assert OrganizationStore.get_membership(org_a.id, owner.id).roles == [:owner]
    end

    test "head coach is set only on coaches ranked below, or on oneself",
         %{owner: owner, org_a: org_a, context_a: context_a} do
      admin = TestFixtures.admin_fixture()
      context = join_as(org_a, admin, [:admin, :coach])

      {:ok, _} = Organizations.set_membership_roles(context_a, owner.id, ["owner", "coach"])

      assert {:error, :role_ceiling_exceeded} =
               Organizations.set_coach_scope(context, owner.id, :all)

      assert {:ok, %{coach_scope: :all}} = Organizations.set_coach_scope(context, admin.id, :all)

      assert {:ok, %{coach_scope: :own}} =
               Organizations.set_coach_scope(context_a, admin.id, :own)
    end
  end

  describe "state owned by the previous role" do
    test "leaving :member cancels that member's active future bookings" do
      admin = TestFixtures.admin_fixture()
      member = TestFixtures.user_fixture(%{role: :member})
      {:ok, organization} = Organizations.create_organization(%{name: "State Owned Booking Gym"})

      for {user, role} <- [{admin, :owner}, {member, :member}] do
        {:ok, _} =
          Organizations.add_membership(%{
            organization_id: organization.id,
            user_id: user.id,
            role: role,
            status: :active,
            joined_at: DateTime.utc_now()
          })
      end

      {:ok, context} = Organizations.resolve_tenant_context(admin, organization.slug)

      Repo.query!("SELECT set_config($1, $2, false)", [
        "app.organization_id",
        context.organization_id
      ])

      Repo.query!("SELECT set_config($1, $2, false)", ["app.user_id", member.id])

      workout = TestFixtures.workout_fixture(admin)
      TestFixtures.class_type_fixture(%{tenant_context: context})
      slot = TestFixtures.slot_fixture(workout, %{auto_approve: false, tenant_context: context})

      assert {:ok, booking} = SubmitBooking.call(context, member, slot.id)
      assert booking.status == :pending

      assert {:ok, updated} = Organizations.set_membership_role(context, member.id, :athlete)
      assert updated.role == :athlete
      assert Scheduling.get_booking(context, booking.id) == nil
    end

    test "archiving assignment access does not reach another organization" do
      admin = TestFixtures.admin_fixture()
      athlete = TestFixtures.user_fixture(%{role: :athlete})
      {:ok, home_org} = Organizations.create_organization(%{name: "Home Assignment Gym"})

      for {user, role} <- [{admin, :owner}, {athlete, :athlete}] do
        {:ok, _} =
          Organizations.add_membership(%{
            organization_id: home_org.id,
            user_id: user.id,
            role: role,
            status: :active,
            joined_at: DateTime.utc_now()
          })
      end

      {:ok, home_context} = Organizations.resolve_tenant_context(admin, home_org.slug)

      Repo.query!("SELECT set_config($1, $2, false)", [
        "app.organization_id",
        home_context.organization_id
      ])

      Repo.query!("SELECT set_config($1, $2, false)", ["app.user_id", admin.id])

      TestFixtures.programming_grant_fixture(home_context, athlete)
      workout = TestFixtures.workout_fixture(admin)

      assert {:ok, assignment} =
               AssignWorkout.call(home_context, %{
                 master_workout_id: workout.id,
                 scheduled_for: Date.utc_today() |> Date.add(1) |> Date.to_iso8601(),
                 athlete_ids: [athlete.id],
                 instructions: "Cross-org coverage"
               })

      # The athlete also belongs to a second gym, where the role change happens.
      {:ok, other_org} = Organizations.create_organization(%{name: "Other Role Gym"})

      for {user, role} <- [{admin, :owner}, {athlete, :athlete}] do
        {:ok, _} =
          Organizations.add_membership(%{
            organization_id: other_org.id,
            user_id: user.id,
            role: role,
            status: :active,
            joined_at: DateTime.utc_now()
          })
      end

      {:ok, other_context} = Organizations.resolve_tenant_context(admin, other_org.slug)

      assert {:ok, _} = Organizations.set_membership_role(other_context, athlete.id, :member)

      # The legacy organization's assignment must survive: it was never in scope.
      assert Workouts.get_assignment_execution_access(home_context, assignment.id, athlete.id)
    end

    test "leaving :athlete archives assignment access while retaining history" do
      admin = TestFixtures.admin_fixture()
      athlete = TestFixtures.user_fixture(%{role: :athlete})
      {:ok, organization} = Organizations.create_organization(%{name: "Athlete Role Gym"})

      for {user, role} <- [{admin, :owner}, {athlete, :athlete}] do
        {:ok, _} =
          Organizations.add_membership(%{
            organization_id: organization.id,
            user_id: user.id,
            role: role,
            status: :active,
            joined_at: DateTime.utc_now()
          })
      end

      {:ok, context} = Organizations.resolve_tenant_context(admin, organization.slug)

      Repo.query!("SELECT set_config($1, $2, false)", [
        "app.organization_id",
        context.organization_id
      ])

      Repo.query!("SELECT set_config($1, $2, false)", ["app.user_id", admin.id])

      TestFixtures.programming_grant_fixture(context, athlete)
      workout = TestFixtures.workout_fixture(admin)

      assert {:ok, assignment} =
               AssignWorkout.call(context, %{
                 master_workout_id: workout.id,
                 scheduled_for: Date.utc_today() |> Date.add(1) |> Date.to_iso8601(),
                 athlete_ids: [athlete.id],
                 instructions: "Role transition coverage"
               })

      assert Workouts.get_assignment_execution_access(context, assignment.id, athlete.id)

      assert {:ok, updated} = Organizations.set_membership_role(context, athlete.id, :member)
      assert updated.role == :member
      assert Workouts.get_assignment_execution_access(context, assignment.id, athlete.id) == nil
      assert Workouts.get_assigned_workout(context, assignment.id).athlete_ids == [athlete.id]
    end
  end

  test "the affected account and this organization's admins are told, and no one else", %{
    member: member,
    org_a: org_a,
    context_a: context_a
  } do
    Phoenix.PubSub.subscribe(Palee.PubSub, "user:sync")

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
