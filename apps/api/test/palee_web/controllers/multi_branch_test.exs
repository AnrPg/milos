defmodule PaleeWeb.MultiBranchTest do
  @moduledoc """
  ADR-186 §7/§8: the page branch filter on reports and «Ισχύει για» on
  create forms. Three branches: the owner sees all; the branch manager
  (admin) works at Κηφισιά and Μαρούσι, not Γλυφάδα.
  """

  use PaleeWeb.ConnCase, async: false

  import Palee.TestFixtures

  alias Palee.{Facility, Finance, Organizations, Repo}

  setup do
    {:ok, organization} =
      Organizations.create_organization(%{name: "Multi #{System.unique_integer([:positive])}"})

    Repo.query!("SELECT set_config($1, $2, false)", ["app.organization_id", organization.id])

    owner = member(organization, :owner)
    {:ok, owner_context} = Organizations.resolve_tenant_context(owner, organization.slug)

    {:ok, kifisia} = Facility.create_location(owner_context, %{name: "Κηφισιά"})
    {:ok, marousi} = Facility.create_location(owner_context, %{name: "Μαρούσι"})
    {:ok, glyfada} = Facility.create_location(owner_context, %{name: "Γλυφάδα"})

    manager = member(organization, :admin)

    {:ok, _scope} =
      Organizations.set_membership_location_scope(owner_context, manager.id, [
        kifisia.id,
        marousi.id
      ])

    %{
      owner: owner,
      owner_context: owner_context,
      manager: manager,
      kifisia: kifisia,
      marousi: marousi,
      glyfada: glyfada,
      workout: workout_fixture(owner, %{tenant_context: owner_context, title: "Multi WOD"}),
      class_type: class_type_fixture(%{tenant_context: owner_context}),
      base: "/api/org/#{organization.slug}/admin",
      organization: organization
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

  defp api(user), do: build_conn() |> put_bearer_token(user)

  defp class_body(ctx, location_ids) do
    %{
      master_workout_id: ctx.workout.id,
      class_type_id: ctx.class_type.id,
      scheduled_at: DateTime.add(DateTime.utc_now(), 7200, :second),
      capacity: 10,
      auto_approve: true,
      booking_timeout_minutes: 60,
      location_ids: location_ids
    }
  end

  defp class_count(ctx) do
    %{rows: [[count]]} =
      Repo.query!("SELECT count(*) FROM scheduled_classes WHERE organization_id = $1", [
        Ecto.UUID.dump!(ctx.organization.id)
      ])

    count
  end

  defp client_with_package(organization, location_ids) do
    user = member(organization, :member)

    {:ok, package} =
      Finance.create_package(%{
        name: "Package #{System.unique_integer([:positive])}",
        package_type: "membership",
        base_price_cents: 5000,
        fields: %{"facility.location_ids" => location_ids}
      })

    {:ok, membership} =
      Finance.upsert_membership(user.id, %{
        user_type_snapshot: "member",
        status: "active",
        signup_source: "direct"
      })

    {:ok, _subscription} = Finance.assign_package(membership.id, package.id, %{})
    user
  end

  describe "«Ισχύει για» on a new class" do
    test "creates one class per branch, all or nothing", ctx do
      before = class_count(ctx)

      created =
        api(ctx.manager)
        |> post("#{ctx.base}/schedule/slots", class_body(ctx, [ctx.kifisia.id, ctx.marousi.id]))
        |> json_response(201)

      assert length(created["slots"]) == 2

      assert created["slots"] |> Enum.map(& &1["location_id"]) |> Enum.sort() ==
               Enum.sort([ctx.kifisia.id, ctx.marousi.id])

      assert class_count(ctx) == before + 2

      # Γλυφάδα is out of the manager's reach: nothing is created at all.
      conn =
        api(ctx.manager)
        |> post("#{ctx.base}/schedule/slots", class_body(ctx, [ctx.kifisia.id, ctx.glyfada.id]))

      assert json_response(conn, 403)["code"] == "location_out_of_scope"
      assert class_count(ctx) == before + 2
    end

    test "a failing branch rolls back the ones already created", ctx do
      before = class_count(ctx)
      {:ok, _archived} = Facility.archive_location(ctx.owner_context, ctx.glyfada.id)

      conn =
        api(ctx.owner)
        |> post("#{ctx.base}/schedule/slots", class_body(ctx, [ctx.kifisia.id, ctx.glyfada.id]))

      assert json_response(conn, 422)
      assert class_count(ctx) == before
    end
  end

  describe "covering items" do
    test "a package is valid at the manager's branches, never beyond", ctx do
      body = %{name: "Κηφισιά only", package_type: "membership", base_price_cents: 4000}

      conn =
        api(ctx.manager)
        |> post(
          "#{ctx.base}/finance/packages",
          Map.put(body, :fields, %{"facility.location_ids" => [ctx.glyfada.id]})
        )

      assert json_response(conn, 403)["code"] == "location_scope_exceeded"

      package =
        api(ctx.manager)
        |> post("#{ctx.base}/finance/packages", Map.put(body, :code, "kifisia_only"))
        |> json_response(201)
        |> Map.fetch!("package")

      # No branches named: the manager's own.
      assert Enum.sort(package["fields"]["facility.location_ids"]) ==
               Enum.sort([ctx.kifisia.id, ctx.marousi.id])

      {:ok, elsewhere} =
        Finance.create_package(%{
          name: "Γλυφάδα",
          package_type: "membership",
          fields: %{"facility.location_ids" => [ctx.glyfada.id]}
        })

      ids =
        api(ctx.manager)
        |> get("#{ctx.base}/finance/packages")
        |> json_response(200)
        |> Map.fetch!("packages")
        |> Enum.map(& &1["id"])

      assert package["id"] in ids
      refute elsewhere.id in ids
    end

    test "a promotion carries branches; «all branches» needs an all-branch scope", ctx do
      conn =
        api(ctx.manager)
        |> post("#{ctx.base}/finance/promotions", %{name: "Everywhere", all_locations: true})

      assert json_response(conn, 403)["code"] == "location_scope_exceeded"

      mine =
        api(ctx.manager)
        |> post("#{ctx.base}/finance/promotions", %{
          name: "Κηφισιά",
          location_ids: [ctx.kifisia.id]
        })
        |> json_response(201)
        |> Map.fetch!("promotion_campaign")

      assert mine["location_scope"] == %{
               "all_locations" => false,
               "location_ids" => [ctx.kifisia.id]
             }

      theirs =
        api(ctx.owner)
        |> post("#{ctx.base}/finance/promotions", %{
          name: "Γλυφάδα",
          location_ids: [ctx.glyfada.id]
        })
        |> json_response(201)
        |> Map.fetch!("promotion_campaign")

      ids =
        api(ctx.manager)
        |> get("#{ctx.base}/finance/promotions")
        |> json_response(200)
        |> Map.fetch!("promotion_campaigns")
        |> Enum.map(& &1["id"])

      assert mine["id"] in ids
      refute theirs["id"] in ids
    end

    test "a coaching assignment stays inside the coach's branches", ctx do
      athlete = member(ctx.organization, :athlete)
      programming_grant_fixture(ctx.organization.id, athlete)

      conn =
        api(ctx.manager)
        |> post("#{ctx.base}/assigned-workouts", %{
          master_workout_id: ctx.workout.id,
          athlete_ids: [athlete.id],
          scheduled_for: Date.to_iso8601(Date.utc_today()),
          location_ids: [ctx.glyfada.id]
        })

      assert json_response(conn, 403)["code"] == "location_scope_exceeded"
    end

    test "seasons and referral programmes are business-wide", ctx do
      conn =
        api(ctx.manager)
        |> post("#{ctx.base}/finance/referral-programs", %{
          name: "Bring a friend",
          reward_type: "credit",
          reward_value: 2_000
        })

      assert json_response(conn, 403)["code"] == "location_scope_exceeded"
    end
  end

  describe "the page branch filter" do
    test "narrows the finance summary and splits it per branch", ctx do
      _at_kifisia = client_with_package(ctx.organization, [ctx.kifisia.id])
      _at_marousi = client_with_package(ctx.organization, [ctx.marousi.id])

      all =
        api(ctx.owner)
        |> get("#{ctx.base}/finance/summary")
        |> json_response(200)

      assert all["branch_filter"] == %{"all_locations" => true, "location_ids" => []}
      assert all["totals"]["active_memberships"] >= 2

      splits = Map.new(all["branches"], &{&1["location_id"], &1})
      assert splits[ctx.kifisia.id]["active_memberships"] == 1
      assert splits[ctx.marousi.id]["active_memberships"] == 1
      assert splits[ctx.glyfada.id]["active_memberships"] == 0

      kifisia =
        api(ctx.owner)
        |> get("#{ctx.base}/finance/summary", %{location_ids: ctx.kifisia.id})
        |> json_response(200)

      assert kifisia["branch_filter"]["location_ids"] == [ctx.kifisia.id]
      assert kifisia["totals"]["active_memberships"] == 1
      assert kifisia["branches"] == []

      # A branch outside the scope is dropped, never widened to.
      glyfada =
        api(ctx.manager)
        |> get("#{ctx.base}/finance/summary", %{location_ids: ctx.glyfada.id})
        |> json_response(200)

      assert glyfada["branch_filter"]["location_ids"] == []
      assert glyfada["totals"]["active_memberships"] == 0
    end

    test "filters the analytics summary", ctx do
      body =
        api(ctx.manager)
        |> get("#{ctx.base}/analytics/summary", %{
          location_ids: "#{ctx.kifisia.id},#{ctx.glyfada.id}"
        })
        |> json_response(200)

      assert body["branch_filter"] == %{
               "all_locations" => false,
               "location_ids" => [ctx.kifisia.id]
             }

      owner_body =
        api(ctx.owner)
        |> get("#{ctx.base}/analytics/summary")
        |> json_response(200)

      assert length(owner_body["branches"]) == 3
    end
  end

  describe "the finance operations lists follow the page filter" do
    defp list_ids(user, path, key, params \\ %{}) do
      body = user |> api() |> get(path, params) |> json_response(200)
      {Enum.map(body[key], & &1["id"]), body["branch_filter"]}
    end

    test "members are listed at their home branch", ctx do
      at_kifisia = client_with_package(ctx.organization, [ctx.kifisia.id])
      at_marousi = client_with_package(ctx.organization, [ctx.marousi.id])
      at_glyfada = client_with_package(ctx.organization, [ctx.glyfada.id])
      path = "#{ctx.base}/finance/members"

      {all, filter} = list_ids(ctx.owner, path, "members")
      assert filter == %{"all_locations" => true, "location_ids" => []}
      assert Enum.all?([at_kifisia.id, at_marousi.id, at_glyfada.id], &(&1 in all))

      {kifisia, filter} = list_ids(ctx.owner, path, "members", %{location_ids: ctx.kifisia.id})
      assert filter == %{"all_locations" => false, "location_ids" => [ctx.kifisia.id]}
      assert kifisia == [at_kifisia.id]

      # A branch outside the manager's scope drops out, never widens the list.
      {mixed, filter} =
        list_ids(ctx.manager, path, "members", %{
          location_ids: "#{ctx.marousi.id},#{ctx.glyfada.id}"
        })

      assert filter["location_ids"] == [ctx.marousi.id]
      assert mixed == [at_marousi.id]
    end

    test "packages valid at a chosen branch or everywhere", ctx do
      package = fn name, ids ->
        {:ok, package} =
          Finance.create_package(%{
            name: name,
            package_type: "membership",
            fields: if(ids, do: %{"facility.location_ids" => ids}, else: %{})
          })

        package.id
      end

      kifisia = package.("Κηφισιά", [ctx.kifisia.id])
      glyfada = package.("Γλυφάδα", [ctx.glyfada.id])
      everywhere = package.("Παντού", nil)
      path = "#{ctx.base}/finance/packages"

      {ids, filter} = list_ids(ctx.owner, path, "packages", %{location_ids: ctx.kifisia.id})
      assert filter["location_ids"] == [ctx.kifisia.id]
      assert kifisia in ids
      assert everywhere in ids
      refute glyfada in ids

      {ids, filter} = list_ids(ctx.manager, path, "packages", %{location_ids: ctx.glyfada.id})
      assert filter["location_ids"] == []
      assert everywhere in ids
      refute glyfada in ids
      refute kifisia in ids

      {ids, _filter} = list_ids(ctx.owner, path, "packages")
      assert Enum.all?([kifisia, glyfada, everywhere], &(&1 in ids))
    end

    test "promotions valid at a chosen branch or everywhere", ctx do
      create = fn body ->
        api(ctx.owner)
        |> post("#{ctx.base}/finance/promotions", body)
        |> json_response(201)
        |> get_in(["promotion_campaign", "id"])
      end

      marousi = create.(%{name: "Μαρούσι", location_ids: [ctx.marousi.id]})
      glyfada = create.(%{name: "Γλυφάδα", location_ids: [ctx.glyfada.id]})
      everywhere = create.(%{name: "Παντού", all_locations: true})
      path = "#{ctx.base}/finance/promotions"

      {ids, filter} =
        list_ids(ctx.manager, path, "promotion_campaigns", %{location_ids: ctx.marousi.id})

      assert filter == %{"all_locations" => false, "location_ids" => [ctx.marousi.id]}
      assert marousi in ids
      assert everywhere in ids
      refute glyfada in ids

      {ids, _filter} =
        list_ids(ctx.owner, path, "promotion_campaigns", %{location_ids: ctx.glyfada.id})

      assert glyfada in ids
      assert everywhere in ids
      refute marousi in ids
    end

    test "referrals and their rewards follow their people", ctx do
      referrer = client_with_package(ctx.organization, [ctx.kifisia.id])
      friend = client_with_package(ctx.organization, [ctx.kifisia.id])
      other = client_with_package(ctx.organization, [ctx.glyfada.id])
      other_friend = client_with_package(ctx.organization, [ctx.glyfada.id])

      {:ok, program} =
        Finance.create_referral_program(%{
          name: "Φέρε φίλο",
          reward_type: "credit",
          reward_value: 1000
        })

      event = fn from, to ->
        {:ok, membership} =
          Finance.upsert_membership(to.id, %{
            user_type_snapshot: "member",
            status: "active",
            signup_source: "direct"
          })

        {:ok, event} =
          Finance.create_referral_event(%{
            referral_program_id: program.id,
            referrer_user_id: from.id,
            referred_user_id: to.id,
            membership_id: membership.id,
            referrer_role_snapshot: "member",
            referred_role_snapshot: "member"
          })

        {:ok, event} = Finance.update_referral_status(event.id, "approved")
        {:ok, reward} = Finance.create_referral_reward(event.id, %{})
        {event.id, reward.id}
      end

      {kifisia_event, kifisia_reward} = event.(referrer, friend)
      {glyfada_event, glyfada_reward} = event.(other, other_friend)
      params = %{location_ids: ctx.kifisia.id}

      {events, filter} =
        list_ids(ctx.owner, "#{ctx.base}/finance/referrals", "referral_events", params)

      assert filter["location_ids"] == [ctx.kifisia.id]
      assert kifisia_event in events
      refute glyfada_event in events

      {rewards, _filter} =
        list_ids(ctx.owner, "#{ctx.base}/finance/referral-rewards", "referral_rewards", params)

      assert kifisia_reward in rewards
      refute glyfada_reward in rewards
    end

    test "refund receipts echo the filter", ctx do
      body =
        api(ctx.manager)
        |> get("#{ctx.base}/finance/refund-receipts", %{location_ids: ctx.glyfada.id})
        |> json_response(200)

      assert body["branch_filter"] == %{"all_locations" => false, "location_ids" => []}
      assert body["refund_receipts"] == []
    end
  end
end
