defmodule MilosTrainingWeb.AdminScaleLevelControllerTest do
  @moduledoc """
  ADR-118 / TD-056: `/api/org/:slug/admin/scale-levels` reads and replaces
  only the addressed tenant's scale levels. Requests run as the RLS-enforcing
  runtime role (ADR-109).
  """

  use MilosTrainingWeb.ConnCase, async: false

  import MilosTraining.TestFixtures

  alias MilosTraining.{Organizations, Workouts}

  setup do
    {org_a, admin_a} = tenant_with_admin!("Scale Gym A")
    {org_b, admin_b} = tenant_with_admin!("Scale Gym B")

    %{org_a: org_a, admin_a: admin_a, org_b: org_b, admin_b: admin_b}
  end

  test "an admin replaces their own tenant's scale levels without touching another's", ctx do
    response =
      ctx.conn
      |> put_bearer_token(ctx.admin_a)
      |> put("/api/org/#{ctx.org_a.slug}/admin/scale-levels", %{
        scale_levels: [
          %{slug: "rx", label: "Prescribed", sort_order: 1},
          %{slug: "elite", label: "Elite", sort_order: 2}
        ]
      })
      |> json_response(200)

    assert Enum.map(response["scale_levels"], & &1["slug"]) == ["rx", "elite"]

    assert labels(ctx.conn, ctx.admin_a, ctx.org_a) == ["Prescribed", "Elite"]
    assert labels(ctx.conn, ctx.admin_b, ctx.org_b) == ["Scaled", "Rx", "Rx+"]
  end

  test "an admin of another tenant can neither read nor replace a tenant's scale levels", ctx do
    read_status =
      ctx.conn
      |> put_bearer_token(ctx.admin_b)
      |> get("/api/org/#{ctx.org_a.slug}/admin/scale-levels")
      |> Map.fetch!(:status)

    write_status =
      ctx.conn
      |> put_bearer_token(ctx.admin_b)
      |> put("/api/org/#{ctx.org_a.slug}/admin/scale-levels", %{
        scale_levels: [%{slug: "hijacked", label: "Hijacked", sort_order: 1}]
      })
      |> Map.fetch!(:status)

    assert read_status in [403, 404]
    assert write_status in [403, 404]
    assert labels(ctx.conn, ctx.admin_a, ctx.org_a) == ["Scaled", "Rx", "Rx+"]
  end

  test "executions materialize their scale slug against the workout's own tenant", ctx do
    {:ok, _} =
      Workouts.replace_scale_levels(%{organization_id: ctx.org_a.id}, [
        %{slug: "scaled", label: "Scaled", sort_order: 1},
        %{slug: "rx", label: "Prescribed", sort_order: 2}
      ])

    workout_b = workout_fixture(ctx.admin_b, scaled_workout_attrs(ctx.org_b, ctx.admin_b))
    member_b = user_fixture()
    add_membership!(ctx.org_b, member_b, :member)

    member_conn = put_bearer_token(ctx.conn, member_b)

    execution =
      member_conn
      |> post("/api/executions", %{
        master_workout_id: workout_b.id,
        scale_level_slug: "rx",
        source: "self_selected"
      })
      |> json_response(201)
      |> Map.fetch!("execution")

    assert execution["organization_id"] == ctx.org_b.id

    shown =
      member_conn
      |> recycle()
      |> get("/api/executions/#{execution["id"]}")
      |> json_response(200)
      |> Map.fetch!("execution")

    assert get_in(shown, ["workout", "scale_level", "slug"]) == "rx"
    assert get_in(shown, ["workout", "scale_level", "label"]) == "Rx"

    [section] = shown["workout"]["sections"]
    [exercise] = section["exercises"]
    assert exercise["prescription_value"] == 8
  end

  defp labels(conn, admin, organization) do
    conn
    |> put_bearer_token(admin)
    |> get("/api/org/#{organization.slug}/admin/scale-levels")
    |> json_response(200)
    |> Map.fetch!("scale_levels")
    |> Enum.map(& &1["label"])
  end

  defp scaled_workout_attrs(organization, admin) do
    %{
      tenant_context: %{organization_id: organization.id, user_id: admin.id},
      sections: [
        %{
          name: "Main Set",
          order: 1,
          scoreable: false,
          exercises: [
            %{
              name: "Thrusters",
              order: 1,
              sets: 3,
              prescription_value: 12,
              prescription_unit: "reps",
              variations: [%{scale_level_slug: "rx", prescription_value: 8}]
            }
          ]
        }
      ]
    }
  end

  defp tenant_with_admin!(name) do
    {:ok, organization} = Organizations.create_organization(%{name: name})
    admin = admin_fixture()
    add_membership!(organization, admin, :owner)
    {:ok, _levels} = Workouts.seed_default_scale_levels(%{organization_id: organization.id})
    {organization, admin}
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
