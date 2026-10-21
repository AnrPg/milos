defmodule Palee.Workouts.TenantScopedReadsTest do
  @moduledoc """
  ADR-133 / TD-094: every Workouts read takes a tenant context. The
  context-free arities that read in whatever session happened to be open are
  gone from the public API.
  """

  use Palee.DataCase, async: false

  @moduletag :rls_enforced

  import Palee.TestFixtures

  alias Palee.{Organizations, Workouts}

  setup do
    owner = admin_fixture()
    athlete = user_fixture(%{role: :athlete})

    {org_a, org_b} =
      bypass_rls(fn ->
        {:ok, org_a} = Organizations.create_organization(%{name: "Scoped Reads A"})
        {:ok, org_b} = Organizations.create_organization(%{name: "Scoped Reads B"})

        for org <- [org_a, org_b] do
          add_member!(org, owner, :owner)
        end

        add_member!(org_a, athlete, :athlete)
        {org_a, org_b}
      end)

    context_a = %{organization_id: org_a.id, user_id: owner.id}
    context_b = %{organization_id: org_b.id, user_id: owner.id}
    {:ok, _} = Workouts.seed_default_scale_levels(context_a)

    workout =
      workout_fixture(owner, %{
        tenant_context: context_a,
        sections: [
          %{
            name: "Main",
            order: 1,
            exercises: [
              %{
                name: "Thrusters",
                order: 1,
                prescription_value: 10,
                prescription_unit: "reps",
                variations: [%{scale_level_slug: "rx", prescription_value: 8}]
              }
            ]
          }
        ]
      })

    {:ok, assignment} =
      Workouts.assign_workout(context_a, %{
        master_workout_id: workout.id,
        athlete_ids: [athlete.id],
        scheduled_for: Date.utc_today()
      })

    %{
      context_a: context_a,
      context_b: context_b,
      workout: workout,
      assignment: assignment,
      exercise_id: workout.sections |> hd() |> Map.get(:exercises) |> hd() |> Map.get(:id)
    }
  end

  test "assignments are read through the owning tenant only", ctx do
    assert {:ok, %{id: id}} = Workouts.get_assignment(ctx.context_a, ctx.assignment.id)
    assert id == ctx.assignment.id
    assert {:error, :not_found} = Workouts.get_assignment(ctx.context_b, ctx.assignment.id)
  end

  test "change targets are listed through the owning tenant only", ctx do
    assert [%{assigned_workout_id: id}] =
             Workouts.list_workout_change_targets(ctx.context_a, ctx.workout.id)

    assert id == ctx.assignment.id
    assert [] == Workouts.list_workout_change_targets(ctx.context_b, ctx.workout.id)
  end

  test "materialization reads the workout in the owning tenant only", ctx do
    assert %{sections: [_ | _]} =
             Workouts.materialize_workout_for_scale(ctx.context_a, ctx.workout.id, "rx")

    assert nil == Workouts.materialize_workout_for_scale(ctx.context_b, ctx.workout.id, "rx")

    assert %{workout: %{id: id}, scales: scales} =
             Workouts.materialize_workout(ctx.context_a, ctx.workout.id)

    assert id == ctx.workout.id
    assert [_ | _] = scales
    assert nil == Workouts.materialize_workout(ctx.context_b, ctx.workout.id)
  end

  test "exercise existence is answered per tenant", ctx do
    assert Workouts.exercise_exists?(ctx.context_a, ctx.exercise_id)
    refute Workouts.exercise_exists?(ctx.context_b, ctx.exercise_id)
  end

  test "the context-free read arities are no longer part of the public API" do
    exported = Workouts.__info__(:functions)

    for read <- [
          get_workout: 1,
          get_workout_for_admin: 1,
          get_assigned_workout: 1,
          get_assignment: 1,
          get_assignment_execution_access: 2,
          list_workouts: 0,
          list_folders: 0,
          list_assigned_workouts_for_admin: 2,
          list_assigned_workouts_for_athlete: 3,
          list_workout_change_targets: 1,
          materialize_workout: 1,
          materialize_workout_for_scale: 2,
          exercise_exists?: 1
        ] do
      refute read in exported, "#{inspect(read)} should take a tenant context"
    end
  end

  defp add_member!(organization, user, role) do
    {:ok, membership} =
      Organizations.add_membership(%{
        organization_id: organization.id,
        user_id: user.id,
        role: role,
        roles: [role],
        status: :active,
        joined_at: DateTime.utc_now()
      })

    membership
  end
end
