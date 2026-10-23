defmodule PaleeWeb.BranchScopedStaffTest do
  @moduledoc """
  ADR-186: staff who work at some branches of a business. A front desk at
  Κηφισιά neither sees nor checks people in at Μαρούσι; a branch manager
  (admin @ Κηφισιά) runs Κηφισιά's classes, grants only inside Κηφισιά and
  loses the gym-wide settings; invitations carry roles and branches.
  """

  use PaleeWeb.ConnCase, async: false

  import Palee.TestFixtures

  alias Palee.{Facility, Organizations, Repo}

  setup do
    {:ok, organization} =
      Organizations.create_organization(%{name: "Branches #{System.unique_integer([:positive])}"})

    Repo.query!("SELECT set_config($1, $2, false)", ["app.organization_id", organization.id])

    owner = member(organization, :owner)
    {:ok, owner_context} = Organizations.resolve_tenant_context(owner, organization.slug)

    {:ok, kifisia} = Facility.create_location(owner_context, %{name: "Κηφισιά"})
    {:ok, marousi} = Facility.create_location(owner_context, %{name: "Μαρούσι"})

    class_type = class_type_fixture(%{tenant_context: owner_context})
    workout = workout_fixture(owner, %{tenant_context: owner_context, title: "Branch WOD"})

    desk = member(organization, :front_desk)
    :ok = scope(owner_context, desk, [kifisia.id])

    manager = member(organization, :admin)
    :ok = scope(owner_context, manager, [kifisia.id])

    %{
      organization: organization,
      owner: owner,
      owner_context: owner_context,
      kifisia: kifisia,
      marousi: marousi,
      workout: workout,
      class_type: class_type,
      desk: desk,
      manager: manager,
      slug: organization.slug
    }
  end

  defp member(organization, role) do
    user = user_fixture()

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

  defp scope(owner_context, user, location_ids) do
    {:ok, _result} =
      Organizations.set_membership_location_scope(owner_context, user.id, location_ids)

    :ok
  end

  defp slot(ctx, location, attrs \\ %{}) do
    slot_fixture(
      ctx.workout,
      Map.merge(%{tenant_context: ctx.owner_context, location_id: location.id}, attrs)
    )
  end

  defp api(conn, user), do: put_bearer_token(conn, user)

  describe "the tenant context and the session payload" do
    test "carry the branches, and branch staff lose gym-wide capabilities", ctx do
      {:ok, desk_context} = Organizations.resolve_tenant_context(ctx.desk, ctx.slug)
      assert desk_context.location_scope == [ctx.kifisia.id]

      {:ok, manager_context} = Organizations.resolve_tenant_context(ctx.manager, ctx.slug)
      refute Organizations.can?(manager_context, :manage_settings)
      # ADR-186 §7: reports follow the branches instead of being withheld.
      assert Organizations.can?(manager_context, :view_finance_reports)
      refute Organizations.can?(manager_context, :manage_finance_settings)
      assert Organizations.can?(manager_context, :manage_schedule)
      assert Organizations.can?(manager_context, :manage_locations)

      assert ctx.owner_context.location_scope == :all

      [membership] =
        build_conn()
        |> api(ctx.manager)
        |> get("/api/memberships")
        |> json_response(200)
        |> Enum.filter(&(&1["organization"]["slug"] == ctx.slug))

      assert membership["location_scope"] == %{
               "all_locations" => false,
               "location_ids" => [ctx.kifisia.id]
             }

      refute Map.has_key?(membership["capabilities"], "manage_settings")
      assert membership["capabilities"]["manage_schedule"] == "all"
    end

    test "an archived branch drops out of the scope", ctx do
      {:ok, _archived} = Facility.archive_location(ctx.owner_context, ctx.kifisia.id)
      {:ok, desk_context} = Organizations.resolve_tenant_context(ctx.desk, ctx.slug)
      assert desk_context.location_scope == []
    end
  end

  describe "a front desk at Κηφισιά" do
    test "sees only Κηφισιά's locations and classes", ctx do
      here = slot(ctx, ctx.kifisia)
      there = slot(ctx, ctx.marousi)

      locations =
        build_conn()
        |> api(ctx.desk)
        |> get("/api/org/#{ctx.slug}/admin/locations")
        |> json_response(200)
        |> Map.fetch!("locations")

      assert Enum.map(locations, & &1["id"]) == [ctx.kifisia.id]

      start_at = DateTime.utc_now() |> DateTime.add(-3600) |> DateTime.to_iso8601()
      end_at = DateTime.utc_now() |> DateTime.add(4 * 86_400) |> DateTime.to_iso8601()

      schedule =
        build_conn()
        |> api(ctx.desk)
        |> get("/api/org/#{ctx.slug}/schedule", %{start_at: start_at, end_at: end_at, days: 7})
        |> json_response(200)

      ids = Enum.map(schedule["slots"], & &1["id"])
      assert here.id in ids
      refute there.id in ids
      assert Enum.map(schedule["locations"], & &1["id"]) == [ctx.kifisia.id]
    end

    test "cannot check anyone in at Μαρούσι, and checks in at Κηφισιά by default", ctx do
      client = member(ctx.organization, :member)

      conn =
        build_conn()
        |> api(ctx.desk)
        |> post("/api/org/#{ctx.slug}/admin/check-ins", %{
          user_id: client.id,
          location_id: ctx.marousi.id
        })

      assert %{"code" => "location_out_of_scope"} = json_response(conn, 403)

      conn =
        build_conn()
        |> api(ctx.desk)
        |> post("/api/org/#{ctx.slug}/admin/check-in/members/#{client.id}", %{
          location_id: ctx.marousi.id
        })

      assert %{"code" => "location_out_of_scope"} = json_response(conn, 403)

      check_in =
        build_conn()
        |> api(ctx.desk)
        |> post("/api/org/#{ctx.slug}/admin/check-ins", %{user_id: client.id})
        |> json_response(201)
        |> Map.fetch!("check_in")

      assert check_in["location_id"] == ctx.kifisia.id
    end

    test "cannot open Μαρούσι's door screen", ctx do
      conn =
        build_conn()
        |> api(ctx.desk)
        |> get("/api/org/#{ctx.slug}/admin/check-in/door/#{ctx.marousi.id}")

      assert json_response(conn, 403)["code"] == "location_out_of_scope"

      assert build_conn()
             |> api(ctx.desk)
             |> get("/api/org/#{ctx.slug}/admin/check-in/door/#{ctx.kifisia.id}")
             |> json_response(200)
    end
  end

  describe "a branch manager (admin @ Κηφισιά)" do
    test "runs Κηφισιά's classes only", ctx do
      there = slot(ctx, ctx.marousi)

      conn =
        build_conn()
        |> api(ctx.manager)
        |> delete("/api/org/#{ctx.slug}/admin/schedule/slots/#{there.id}")

      assert json_response(conn, 403)["code"] == "location_out_of_scope"

      body = %{
        master_workout_id: ctx.workout.id,
        class_type_id: ctx.class_type.id,
        scheduled_at: DateTime.add(DateTime.utc_now(), 7200, :second),
        capacity: 10,
        auto_approve: true,
        booking_timeout_minutes: 60
      }

      for location_id <- [ctx.marousi.id, nil] do
        conn =
          build_conn()
          |> api(ctx.manager)
          |> post(
            "/api/org/#{ctx.slug}/admin/schedule/slots",
            Map.put(body, :location_id, location_id)
          )

        assert json_response(conn, 403)["code"] == "location_out_of_scope"
      end

      created =
        build_conn()
        |> api(ctx.manager)
        |> post(
          "/api/org/#{ctx.slug}/admin/schedule/slots",
          Map.put(body, :location_id, ctx.kifisia.id)
        )
        |> json_response(201)

      # Moving it to Μαρούσι is out of reach too.
      conn =
        build_conn()
        |> api(ctx.manager)
        |> patch(
          "/api/org/#{ctx.slug}/admin/schedule/slots/#{created["slot"]["id"]}",
          Map.put(body, :location_id, ctx.marousi.id)
        )

      assert json_response(conn, 403)["code"] == "location_out_of_scope"
    end

    test "cannot change gym-wide settings or open a new branch", ctx do
      conn =
        build_conn()
        |> api(ctx.manager)
        |> post("/api/org/#{ctx.slug}/admin/locations", %{name: "Γλυφάδα"})

      assert json_response(conn, 403)

      assert build_conn()
             |> api(ctx.manager)
             |> patch("/api/org/#{ctx.slug}/admin/locations/#{ctx.kifisia.id}", %{
               name: "Κηφισιά Κέντρο"
             })
             |> json_response(200)

      conn =
        build_conn()
        |> api(ctx.manager)
        |> patch("/api/org/#{ctx.slug}/admin/locations/#{ctx.marousi.id}", %{name: "Χαλάνδρι"})

      assert json_response(conn, 403)["code"] == "location_out_of_scope"
    end

    test "cannot grant beyond their branches", ctx do
      client = member(ctx.organization, :member)
      path = "/api/org/#{ctx.slug}/admin/users/#{client.id}"

      for body <- [%{all_locations: true}, %{location_ids: [ctx.kifisia.id, ctx.marousi.id]}] do
        conn = build_conn() |> api(ctx.manager) |> put(path <> "/location-scope", body)
        assert json_response(conn, 403)["code"] == "location_scope_exceeded"
      end

      # A member with «every branch» cannot be made staff by a branch manager…
      conn = build_conn() |> api(ctx.manager) |> put(path <> "/roles", %{roles: ["front_desk"]})
      assert json_response(conn, 403)["code"] == "location_scope_exceeded"

      # …until they are scoped to the manager's branch.
      assert %{"location_scope" => %{"all_locations" => false, "location_ids" => [kifisia]}} =
               build_conn()
               |> api(ctx.manager)
               |> put(path <> "/location-scope", %{location_ids: [ctx.kifisia.id]})
               |> json_response(200)

      assert kifisia == ctx.kifisia.id

      assert build_conn()
             |> api(ctx.manager)
             |> put(path <> "/roles", %{roles: ["front_desk", "member"]})
             |> json_response(200)

      # Staff of Μαρούσι are out of reach.
      other = member(ctx.organization, :coach)
      :ok = scope(ctx.owner_context, other, [ctx.marousi.id])
      other_path = "/api/org/#{ctx.slug}/admin/users/#{other.id}"

      conn = build_conn() |> api(ctx.manager) |> put(other_path <> "/roles", %{roles: ["member"]})
      assert json_response(conn, 403)["code"] == "location_scope_exceeded"

      conn =
        build_conn()
        |> api(ctx.manager)
        |> put(other_path <> "/location-scope", %{location_ids: [ctx.kifisia.id]})

      assert json_response(conn, 403)["code"] == "location_scope_exceeded"

      # Nor can anyone scope an owner, or a branch manager widen themselves.
      co_owner = member(ctx.organization, :owner)

      conn =
        build_conn()
        |> api(ctx.owner)
        |> put("/api/org/#{ctx.slug}/admin/users/#{co_owner.id}/location-scope", %{
          location_ids: [ctx.kifisia.id]
        })

      assert json_response(conn, 422)["code"] == "owner_location_scope"

      conn =
        build_conn()
        |> api(ctx.manager)
        |> put("/api/org/#{ctx.slug}/admin/users/#{ctx.manager.id}/location-scope", %{
          all_locations: true
        })

      assert json_response(conn, 403)
    end
  end

  describe "invitations" do
    test "carry a role set and branches, never beyond the issuer's", ctx do
      path = "/api/org/#{ctx.slug}/invitations"

      conn =
        build_conn()
        |> api(ctx.manager)
        |> post(path, %{roles: ["coach"], location_ids: [ctx.marousi.id]})

      assert json_response(conn, 403)["code"] == "location_scope_exceeded"

      conn = build_conn() |> api(ctx.manager) |> post(path, %{roles: ["admin"]})
      assert json_response(conn, 403)["code"] == "role_ceiling_exceeded"

      # No branches named: the issuer's own.
      issued =
        build_conn()
        |> api(ctx.manager)
        |> post(path, %{roles: ["front_desk", "member"]})
        |> json_response(201)

      assert issued["role"] == "front_desk"
      assert issued["roles"] == ["front_desk", "member"]

      assert issued["location_scope"] == %{
               "all_locations" => false,
               "location_ids" => [ctx.kifisia.id]
             }

      invited = user_fixture()

      membership =
        build_conn()
        |> api(invited)
        |> post("/api/memberships/redeem", %{invitation_token: issued["token"]})
        |> json_response(201)

      assert membership["roles"] == ["front_desk", "member"]
      assert membership["location_scope"]["location_ids"] == [ctx.kifisia.id]

      {:ok, context} = Organizations.resolve_tenant_context(invited, ctx.slug)
      assert context.location_scope == [ctx.kifisia.id]
    end

    test "the owner invites a coach to two branches; old single-role links still work", ctx do
      path = "/api/org/#{ctx.slug}/invitations"

      issued =
        build_conn()
        |> api(ctx.owner)
        |> post(path, %{
          roles: ["coach"],
          location_ids: [ctx.marousi.id, ctx.kifisia.id]
        })
        |> json_response(201)

      assert Enum.sort(issued["location_scope"]["location_ids"]) ==
               Enum.sort([ctx.kifisia.id, ctx.marousi.id])

      legacy =
        build_conn() |> api(ctx.owner) |> post(path, %{role: "coach"}) |> json_response(201)

      assert legacy["roles"] == ["coach"]
      assert legacy["location_scope"]["all_locations"] == true

      invited = user_fixture()

      build_conn()
      |> api(invited)
      |> post("/api/memberships/redeem", %{invitation_token: legacy["token"]})
      |> json_response(201)

      {:ok, context} = Organizations.resolve_tenant_context(invited, ctx.slug)
      assert context.location_scope == :all
    end
  end
end
