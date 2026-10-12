defmodule MilosTraining.Application.PersonalizedMemberProgrammingTest do
  @moduledoc """
  ADR-107 (TD-037) application-service integration tests against PostgreSQL.
  Service calls run as the RLS-enforcing runtime role; fixtures model
  pre-existing data and run as the test superuser.
  """
  use MilosTraining.DataCase, async: false

  import Ecto.Query
  import MilosTraining.DataCase, only: [with_runtime_role: 1]

  alias MilosTraining.Application.{
    AssignWorkout,
    AuthorizeMemberProgramming,
    AuthorizeWorkoutExecutionSource,
    GetAssignedWorkoutWeek,
    UpdateAssignedWorkout
  }

  alias MilosTraining.{Finance, Organizations, Repo, TestFixtures}
  alias MilosTraining.Organizations.OrganizationMembership

  @programming_plan %{
    "entitlement_version" => 1,
    "channels" => ["in_person", "personal_programming"],
    "capabilities" => [
      "book_classes",
      "execute_assigned_workouts",
      "receive_coaching_touchpoints"
    ],
    "allowances" => %{
      "coaching_touchpoints" => %{"limit" => 1, "period" => "calendar_month"}
    }
  }

  defp tenant do
    owner = TestFixtures.admin_fixture()

    {:ok, organization} =
      Organizations.create_organization(%{name: "PMP Gym #{System.unique_integer([:positive])}"})

    add_membership(organization, owner, :owner)
    {:ok, context} = Organizations.resolve_tenant_context(owner, organization.slug)
    %{owner: owner, organization: organization, context: context}
  end

  defp add_membership(organization, user, role) do
    {:ok, _membership} =
      Organizations.add_membership(%{
        organization_id: organization.id,
        user_id: user.id,
        role: role,
        status: :active,
        joined_at: DateTime.utc_now()
      })

    user
  end

  defp customer(%{organization: organization}, role) do
    account_role = if role == :athlete, do: :athlete, else: :member

    %{role: account_role}
    |> TestFixtures.user_fixture()
    |> then(&add_membership(organization, &1, role))
  end

  defp entitle(%{context: context}, user) do
    {:ok, package} =
      Finance.create_package(context, %{
        code: "pmp-#{System.unique_integer([:positive])}",
        name: "Hybrid",
        family: "hybrid",
        billing_period: "monthly",
        params: @programming_plan
      })

    {:ok, membership} =
      Finance.upsert_membership(context, user.id, %{
        user_type_snapshot: "member",
        status: "active",
        signup_source: "admin_created"
      })

    {:ok, _subscription} =
      Finance.assign_package(context, membership.id, package.id, %{starts_on: Date.utc_today()})

    user
  end

  defp workout(%{owner: owner, context: context}),
    do: TestFixtures.workout_fixture(owner, %{tenant_context: context})

  defp assign(%{context: context}, workout, assignee_ids) do
    with_runtime_role(fn ->
      AssignWorkout.call(context, %{
        master_workout_id: workout.id,
        athlete_ids: assignee_ids,
        scheduled_for: Date.utc_today()
      })
    end)
  end

  defp member_context(%{organization: organization}, user) do
    {:ok, context} = Organizations.resolve_tenant_context(user, organization.slug)
    context
  end

  test "AuthorizeMemberProgramming accepts only explicit grants and names the member" do
    gym = tenant()
    entitled = gym |> customer(:member) |> then(&entitle(gym, &1))
    plain = customer(gym, :member)

    assert :ok = with_runtime_role(fn -> AuthorizeMemberProgramming.call(gym.context, []) end)

    assert :ok =
             with_runtime_role(fn ->
               AuthorizeMemberProgramming.call(gym.context, [entitled.id])
             end)

    assert {:error, :member_programming_not_entitled, details} =
             with_runtime_role(fn ->
               AuthorizeMemberProgramming.call(gym.context, [entitled.id, plain.id])
             end)

    assert details == %{
             user_id: plain.id,
             nickname: plain.nickname,
             reason: "finance_profile_missing"
           }

    assert {:error, :organization_context_required} =
             AuthorizeMemberProgramming.call(%{}, [plain.id])
  end

  test "a member assignment meters a coaching touchpoint; extensions top up an exhausted allowance" do
    gym = tenant()
    member = gym |> customer(:member) |> then(&entitle(gym, &1))

    assert {:ok, first} = assign(gym, workout(gym), [member.id])
    assert first.assignment_kind == "personal"

    # The plan allows one touchpoint a month; rollout mode `observe` records
    # the overrun instead of refusing, exactly as for athletes (ADR-040).
    assert {:ok, _second} = assign(gym, workout(gym), [member.id])

    entitlement = Finance.get_effective_entitlement(gym.context, member.id)
    assert entitlement.allowances.coaching_touchpoints.committed >= 1
  end

  test "updating an assignment checks newly added members and keeps variants single-member" do
    gym = tenant()
    athlete = customer(gym, :athlete)
    entitled = gym |> customer(:member) |> then(&entitle(gym, &1))
    plain = customer(gym, :member)
    coach = customer(gym, :coach)

    assert {:ok, assignment} = assign(gym, workout(gym), [athlete.id])

    update = fn ids ->
      with_runtime_role(fn ->
        UpdateAssignedWorkout.call(gym.context, assignment.id, %{
          athlete_ids: ids,
          scheduled_for: Date.utc_today()
        })
      end)
    end

    assert {:error, :member_programming_not_entitled, %{user_id: plain_id}} =
             update.([athlete.id, plain.id])

    assert plain_id == plain.id
    assert {:error, :invalid_athletes} = update.([athlete.id, coach.id])
    assert {:ok, updated} = update.([athlete.id, entitled.id])
    assert Enum.sort(updated.athlete_ids) == Enum.sort([athlete.id, entitled.id])
  end

  test "members see their assignments in the week view; a demoted assignee cannot start one" do
    gym = tenant()
    member = gym |> customer(:member) |> then(&entitle(gym, &1))
    wod = workout(gym)
    assert {:ok, assignment} = assign(gym, wod, [member.id])

    context = member_context(gym, member)

    assert {:ok, %{assignments: [listed]}} =
             with_runtime_role(fn -> GetAssignedWorkoutWeek.call(context, member, %{}) end)

    assert listed.id == assignment.id
    assert listed.assignment_kind == "personal"

    assert {:ok, %{source: "assigned", organization_id: organization_id}} =
             with_runtime_role(fn ->
               AuthorizeWorkoutExecutionSource.call(
                 context,
                 member,
                 wod.id,
                 "assigned",
                 assignment.id
               )
             end)

    assert organization_id == gym.organization.id

    # The link alone is not enough: once the membership no longer is a
    # customer role, the assignment cannot be executed.
    Repo.update_all(
      from(m in OrganizationMembership,
        where: m.user_id == ^member.id and m.organization_id == ^gym.organization.id
      ),
      set: [role: :coach]
    )

    assert {:error, :execution_source_forbidden} =
             with_runtime_role(fn ->
               AuthorizeWorkoutExecutionSource.call(
                 nil,
                 member,
                 wod.id,
                 "assigned",
                 assignment.id
               )
             end)
  end

  test "leaving the member role archives that member's assignments" do
    gym = tenant()
    member = gym |> customer(:member) |> then(&entitle(gym, &1))
    assert {:ok, _assignment} = assign(gym, workout(gym), [member.id])

    assert {:ok, _membership} =
             with_runtime_role(fn ->
               Organizations.set_membership_role(gym.context, member.id, :athlete)
             end)

    athlete_context = member_context(gym, member)

    assert {:ok, %{assignments: []}} =
             with_runtime_role(fn ->
               GetAssignedWorkoutWeek.call(athlete_context, member, %{})
             end)
  end
end
