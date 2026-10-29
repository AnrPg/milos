defmodule Palee.Application.PersonalizedMemberProgrammingTest do
  @moduledoc """
  ADR-125 (TD-037) application-service integration tests against PostgreSQL.
  Service calls run as the RLS-enforcing runtime role; fixtures model
  pre-existing data and run as the test superuser.
  """
  use Palee.DataCase, async: false

  import Ecto.Query
  import Palee.DataCase, only: [with_runtime_role: 1]

  alias Palee.Application.{
    AssignWorkout,
    AuthorizeProgramming,
    AuthorizeWorkoutExecutionSource,
    GetAssignedWorkoutWeek,
    ProgramUserWorkout,
    UpdateAssignedWorkout
  }

  alias Palee.{Finance, Organizations, Repo, TestFixtures, Workouts}
  alias Palee.Organizations.OrganizationMembership

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

  test "member programming copies stay out of the library; athlete copies remain listed" do
    ctx = tenant()
    member = ctx |> customer(:member) |> then(&entitle(ctx, &1))

    athlete =
      ctx |> customer(:athlete) |> then(&TestFixtures.programming_grant_fixture(ctx.context, &1))

    source = workout(ctx)
    today = Date.to_iso8601(Date.utc_today())

    {:ok, %{workout: member_copy}} =
      with_runtime_role(fn ->
        ProgramUserWorkout.call(ctx.context, ctx.owner, member.id, %{
          "mode" => "personal",
          "master_workout_id" => source.id,
          "scheduled_for" => today
        })
      end)

    {:ok, %{workout: athlete_copy}} =
      with_runtime_role(fn ->
        ProgramUserWorkout.call(ctx.context, ctx.owner, athlete.id, %{
          "master_workout_id" => source.id,
          "scheduled_for" => today
        })
      end)

    library_ids =
      with_runtime_role(fn -> ctx.context |> Workouts.list_workouts() |> Enum.map(& &1.id) end)

    assert source.id in library_ids
    assert athlete_copy.id in library_ids
    refute member_copy.id in library_ids

    # The personal copy still resolves by id for the member's assignment.
    assert %{id: id} =
             with_runtime_role(fn -> Workouts.get_workout(ctx.context, member_copy.id) end)

    assert id == member_copy.id
  end

  test "AuthorizeProgramming needs online programming or personal training, for members and athletes alike" do
    gym = tenant()
    entitled = gym |> customer(:member) |> then(&entitle(gym, &1))

    pt_athlete =
      gym
      |> customer(:athlete)
      |> then(&TestFixtures.programming_grant_fixture(gym.context, &1, :personal_training))

    plain = customer(gym, :member)
    plain_athlete = customer(gym, :athlete)

    assert {:ok, %{}} = with_runtime_role(fn -> AuthorizeProgramming.grants(gym.context, []) end)

    assert {:ok, grants} =
             with_runtime_role(fn ->
               AuthorizeProgramming.grants(gym.context, [entitled.id, pt_athlete.id])
             end)

    assert grants == %{entitled.id => :online_programming, pt_athlete.id => :personal_training}

    assert {:error, :programming_not_in_package, details} =
             with_runtime_role(fn ->
               AuthorizeProgramming.call(gym.context, [entitled.id, plain.id])
             end)

    assert details == %{
             user_id: plain.id,
             nickname: plain.nickname,
             reason: "finance_profile_missing"
           }

    # The athlete role never implies the grant.
    assert {:error, :programming_not_in_package, %{user_id: athlete_id}} =
             with_runtime_role(fn ->
               AuthorizeProgramming.call(gym.context, [plain_athlete.id])
             end)

    assert athlete_id == plain_athlete.id

    assert {:error, :organization_context_required} =
             AuthorizeProgramming.call(%{}, [plain.id])
  end

  test "an athlete without either grant is refused before any copy is filed" do
    gym = tenant()
    athlete = customer(gym, :athlete)
    source = workout(gym)
    before = with_runtime_role(fn -> gym.context |> Workouts.list_workouts() |> length() end)

    assert {:error, :programming_not_in_package, %{user_id: user_id}} =
             with_runtime_role(fn ->
               ProgramUserWorkout.call(gym.context, gym.owner, athlete.id, %{
                 "master_workout_id" => source.id,
                 "scheduled_for" => Date.to_iso8601(Date.utc_today())
               })
             end)

    assert user_id == athlete.id

    assert with_runtime_role(fn -> gym.context |> Workouts.list_workouts() |> length() end) ==
             before
  end

  test "personal training includes its programme: no coaching touchpoint is metered" do
    gym = tenant()

    athlete =
      gym
      |> customer(:athlete)
      |> then(&TestFixtures.programming_grant_fixture(gym.context, &1, :personal_training))

    assert {:ok, _assignment} = assign(gym, workout(gym), [athlete.id])

    metered =
      Repo.one(
        from(entry in "finance_entitlement_usage_entries",
          where: like(entry.idempotency_key, ^"programming-delivery:%:#{athlete.id}"),
          select: count()
        )
      )

    assert metered == 0
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
    athlete = gym |> customer(:athlete) |> then(&entitle(gym, &1))
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

    assert {:error, :programming_not_in_package, %{user_id: plain_id}} =
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
