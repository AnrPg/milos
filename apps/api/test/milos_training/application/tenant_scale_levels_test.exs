defmodule MilosTraining.Application.TenantScaleLevelsTest do
  @moduledoc """
  ADR-128 / TD-063: scale levels are owned per organization. Replacing one
  tenant's set must never touch, reveal or depend on another tenant's.
  """

  use MilosTraining.DataCase, async: false

  @moduletag :rls_enforced

  import MilosTraining.TestFixtures

  alias MilosTraining.Application.{ListScaleLevels, ReplaceScaleLevels}
  alias MilosTraining.{Organizations, ScaleLevel, Workouts}

  setup do
    {org_a, owner_a, context_a} = bypass_rls(fn -> tenant_with_owner!("Scale Tenant A") end)
    {org_b, owner_b, context_b} = bypass_rls(fn -> tenant_with_owner!("Scale Tenant B") end)

    {:ok, _} = Workouts.seed_default_scale_levels(context_a)
    {:ok, _} = Workouts.seed_default_scale_levels(context_b)

    %{
      org_a: org_a,
      org_b: org_b,
      owner_a: owner_a,
      owner_b: owner_b,
      context_a: context_a,
      context_b: context_b
    }
  end

  test "seeding gives each tenant its own default set and is idempotent", ctx do
    levels_a = ListScaleLevels.call(ctx.context_a)
    levels_b = ListScaleLevels.call(ctx.context_b)

    assert Enum.map(levels_a, &{&1.slug, &1.label, &1.sort_order}) == [
             {"scaled", "Scaled", 1},
             {"rx", "Rx", 2},
             {"rx-plus", "Rx+", 3}
           ]

    assert Enum.map(levels_b, &{&1.slug, &1.label}) == Enum.map(levels_a, &{&1.slug, &1.label})
    assert MapSet.disjoint?(ids(levels_a), ids(levels_b))

    assert {:ok, reseeded} = Workouts.seed_default_scale_levels(ctx.context_a)
    assert ids(reseeded) == ids(levels_a)
  end

  test "an admin replaces only their own tenant's scale levels", ctx do
    levels_b_before = ListScaleLevels.call(ctx.context_b)

    assert {:ok, replaced} =
             ReplaceScaleLevels.call(ctx.context_a, [
               %{"slug" => "rx", "label" => "Prescribed", "sort_order" => 1},
               %{"slug" => "elite", "label" => "Elite", "sort_order" => 2}
             ])

    assert Enum.map(replaced, &{&1.slug, &1.label}) == [{"rx", "Prescribed"}, {"elite", "Elite"}]

    assert Enum.map(ListScaleLevels.call(ctx.context_a), &{&1.slug, &1.label, &1.sort_order}) ==
             [{"rx", "Prescribed", 1}, {"elite", "Elite", 2}]

    assert ListScaleLevels.call(ctx.context_b) == levels_b_before
  end

  test "a tenant session can neither see nor modify another tenant's rows", ctx do
    a_ids = ctx.context_a |> ListScaleLevels.call() |> Enum.map(& &1.id)

    Workouts.with_tenant_context(ctx.context_b, fn ->
      visible = Repo.all(from level in ScaleLevel, select: level.organization_id)
      assert visible != []
      assert Enum.all?(visible, &(&1 == ctx.org_b.id))

      assert {0, _} =
               Repo.update_all(from(level in ScaleLevel, where: level.id in ^a_ids),
                 set: [label: "Hijacked"]
               )

      assert {0, _} = Repo.delete_all(from(level in ScaleLevel, where: level.id in ^a_ids))
    end)

    assert Enum.map(ListScaleLevels.call(ctx.context_a), & &1.label) == ["Scaled", "Rx", "Rx+"]
  end

  test "a row written from one tenant's session is stamped with that tenant", ctx do
    Workouts.with_tenant_context(ctx.context_b, fn ->
      assert {:ok, level} =
               %ScaleLevel{}
               |> ScaleLevel.changeset(%{
                 organization_id: ctx.org_a.id,
                 slug: "forged",
                 label: "Forged",
                 sort_order: 9
               })
               |> Repo.insert()

      # The tenant-context trigger overrides the forged organization_id.
      assert Repo.get!(ScaleLevel, level.id).organization_id == ctx.org_b.id
    end)

    refute "forged" in Enum.map(all_levels(ctx.context_a), & &1.slug)
  end

  test "removal guard only counts the acting tenant's workouts", ctx do
    {:ok, _workout} =
      Workouts.create_workout(ctx.context_a, ctx.owner_a, workout_params("rx-plus"))

    without_rx_plus = [
      %{slug: "scaled", label: "Scaled", sort_order: 1},
      %{slug: "rx", label: "Rx", sort_order: 2}
    ]

    assert {:ok, _} = ReplaceScaleLevels.call(ctx.context_b, without_rx_plus)
    assert {:error, changeset} = ReplaceScaleLevels.call(ctx.context_a, without_rx_plus)
    assert errors_on(changeset).scale_levels |> hd() =~ "still used by workout variations"
  end

  test "workouts resolve scale slugs within their own organization", ctx do
    assert {:ok, _} =
             ReplaceScaleLevels.call(ctx.context_b, [
               %{slug: "beginner", label: "Beginner", sort_order: 1}
             ])

    assert {:ok, workout_a} =
             Workouts.create_workout(ctx.context_a, ctx.owner_a, workout_params("rx"))

    assert [%{slug: "rx", label: "Rx", id: rx_id}] = workout_a.available_scale_levels
    assert rx_id in ids(ListScaleLevels.call(ctx.context_a))

    # B has no "rx" any more, even though A does.
    assert {:error, %Ecto.Changeset{}} =
             Workouts.create_workout(ctx.context_b, ctx.owner_b, workout_params("rx"))
  end

  test "fails closed without an organization context", ctx do
    assert {:error, :organization_context_required} =
             ReplaceScaleLevels.call(%{user_id: ctx.owner_a.id}, [
               %{slug: "rx", label: "Rx", sort_order: 1}
             ])

    assert {:error, :organization_context_required} = ListScaleLevels.call(nil)
    assert {:error, :organization_context_required} = Workouts.seed_default_scale_levels(%{})
  end

  defp all_levels(context) do
    Workouts.with_tenant_context(context, fn -> Repo.all(ScaleLevel) end)
  end

  defp ids(levels), do: MapSet.new(levels, & &1.id)

  defp workout_params(scale_slug) do
    %{
      title: "Scaled Ladder #{System.unique_integer([:positive])}",
      type: "crossfit",
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
              variations: [%{scale_level_slug: scale_slug, prescription_value: 6}]
            }
          ]
        }
      ]
    }
  end

  defp tenant_with_owner!(name) do
    {:ok, organization} = Organizations.create_organization(%{name: name})
    owner = user_fixture()
    add_membership!(organization, owner, :owner)

    {:ok, context} = Organizations.resolve_tenant_context(owner, organization.slug)
    {organization, owner, context}
  end

  defp add_membership!(organization, user, role) do
    {:ok, membership} =
      Organizations.add_membership(%{
        organization_id: organization.id,
        user_id: user.id,
        role: role,
        status: :active,
        joined_at: DateTime.utc_now()
      })

    membership
  end
end
