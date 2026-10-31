defmodule PaleeWeb.PackageRequestControllerTest do
  @moduledoc """
  ADR-291 end to end: a box without online payments lists its paid packages;
  a member asks for one («Το θέλω»), it waits 14 days as «Περιμένει πληρωμή»
  granting nothing, shows in the desk's queue with the member, and the
  desk's «Είσπραξη» records the money and assigns the package in one step.
  """
  use PaleeWeb.ConnCase, async: false

  alias Palee.Application.Finance.PackageRequests
  alias Palee.Application.{PublishBoxPublicProfile, UpdateBoxPublicProfile}
  alias Palee.{Finance, Organizations}
  alias Palee.Finance.PackageRequestStore
  alias Palee.Workers.LapsePackageRequestsJob

  import Palee.TestFixtures

  setup do
    admin = admin_fixture(%{nickname: "request_desk"})
    member = user_fixture(%{role: :member, nickname: "request_member"})
    other = user_fixture(%{role: :member, nickname: "request_other"})
    {organization, context} = tenant_fixture(admin, "Desk Request Tenant")
    add_tenant_member(organization, member, :member)
    add_tenant_member(organization, other, :member)

    package = fn name, cents ->
      {:ok, package} =
        Finance.create_package(context, %{
          name: name,
          family: "unlimited",
          billing_period: "monthly",
          base_price_cents: cents
        })

      package
    end

    %{
      admin: admin,
      member: member,
      other: other,
      organization: organization,
      context: context,
      monthly: package.("Μηνιαίο απεριόριστο", 7_000),
      free: package.("Δωρεάν γνωριμία", 0)
    }
  end

  defp member_path(ctx, path), do: "/api/org/#{ctx.organization.slug}/me#{path}"
  defp admin_path(ctx, path), do: "/api/org/#{ctx.organization.slug}/admin#{path}"

  defp ask(conn, ctx, package, user \\ nil) do
    conn
    |> put_bearer_token(user || ctx.member)
    |> post(member_path(ctx, "/packages/#{package.id}/request"), %{})
  end

  defp desk_queue(conn, ctx) do
    conn
    |> put_bearer_token(ctx.admin)
    |> get(admin_path(ctx, "/finance/package-requests"))
    |> json_response(200)
    |> Map.fetch!("requests")
  end

  defp collect(conn, ctx, request_id, method \\ "cash") do
    conn
    |> put_bearer_token(ctx.admin)
    |> post(admin_path(ctx, "/finance/package-requests/#{request_id}/collect"), %{
      payment_method: method
    })
  end

  test "the public package page lists paid packages without online payments",
       %{conn: conn} = ctx do
    {:ok, profile} =
      UpdateBoxPublicProfile.call(ctx.context, %{"about" => "Box", "disciplines" => ["crossfit"]})

    {:ok, _profile} =
      PublishBoxPublicProfile.publish(ctx.context, %{"lock_version" => profile.lock_version})

    page =
      conn
      |> get("/api/public/boxes/#{ctx.organization.slug}/packages")
      |> json_response(200)

    assert page["online_payments"] == false
    assert Enum.map(page["packages"], & &1["name"]) == ["Μηνιαίο απεριόριστο"]
  end

  test "a member asks for a package and it waits 14 days, granting nothing",
       %{conn: conn} = ctx do
    body = conn |> ask(ctx, ctx.monthly) |> json_response(201)

    assert body["created"] == true
    request = body["request"]
    assert request["status"] == "pending"
    assert request["price_cents"] == 7_000
    assert request["hold_days"] == 14
    assert request["days_left"] == 14
    assert request["hold_until"] == gym_today() |> Date.add(14) |> Date.to_iso8601()

    # Asking again returns the same request.
    again = conn |> ask(ctx, ctx.monthly) |> json_response(200)
    assert again["created"] == false
    assert again["request"]["id"] == request["id"]

    mine =
      conn
      |> put_bearer_token(ctx.member)
      |> get(member_path(ctx, "/package-requests"))
      |> json_response(200)

    assert [%{"id" => id}] = mine["requests"]
    assert id == request["id"]

    # No subscription and nothing owed until the desk takes the money.
    profile = Finance.get_member_profile(ctx.context, ctx.member.id)
    assert profile == nil or (profile[:subscriptions] || []) == []
  end

  test "free packages and packages the owner keeps off cannot be asked for",
       %{conn: conn} = ctx do
    assert %{"code" => "package_not_for_sale"} =
             conn |> ask(ctx, ctx.free) |> json_response(409)

    {:ok, _off} =
      Finance.update_package(ctx.context, ctx.monthly.id, %{
        sold_online: false,
        sold_online_chosen_at: DateTime.utc_now()
      })

    assert %{"code" => "package_not_for_sale"} =
             conn |> ask(ctx, ctx.monthly) |> json_response(409)
  end

  test "the desk sees who asked and «Είσπραξη» activates the package", %{conn: conn} = ctx do
    request = conn |> ask(ctx, ctx.monthly) |> json_response(201) |> Map.fetch!("request")

    assert [row] = desk_queue(conn, ctx)
    assert row["id"] == request["id"]
    assert row["person"]["user_id"] == ctx.member.id
    assert row["person"]["handle"] == ctx.member.handle

    collected = conn |> collect(ctx, request["id"]) |> json_response(200)

    assert collected["request"]["status"] == "activated"
    assert collected["received"]["amount_cents"] == 7_000
    assert collected["received"]["membership_package_subscription_id"]

    profile = Finance.get_member_profile(ctx.context, ctx.member.id)
    assert profile.membership

    # Pressed twice: the money is recorded once.
    assert %{"code" => "package_request_closed"} =
             conn |> collect(ctx, request["id"]) |> json_response(409)

    assert desk_queue(conn, ctx) == []
  end

  test "a desk payment needs a desk payment method", %{conn: conn} = ctx do
    request = conn |> ask(ctx, ctx.monthly) |> json_response(201) |> Map.fetch!("request")
    assert conn |> collect(ctx, request["id"], "online") |> json_response(422)
  end

  test "the member takes a request back; nobody else can", %{conn: conn} = ctx do
    request = conn |> ask(ctx, ctx.monthly) |> json_response(201) |> Map.fetch!("request")
    path = member_path(ctx, "/package-requests/#{request["id"]}/cancel")

    assert conn |> put_bearer_token(ctx.other) |> post(path, %{}) |> json_response(404)

    cancelled = conn |> put_bearer_token(ctx.member) |> post(path, %{}) |> json_response(200)
    assert cancelled["request"]["status"] == "cancelled"
    assert desk_queue(conn, ctx) == []

    assert %{"code" => "package_request_closed"} =
             conn |> put_bearer_token(ctx.member) |> post(path, %{}) |> json_response(409)
  end

  test "after 14 days a request leaves the queue and is closed as lapsed",
       %{conn: conn} = ctx do
    {:ok, old, :created} =
      PackageRequestStore.with_tenant_context(ctx.context, fn ->
        PackageRequestStore.request(%{
          user_id: ctx.member.id,
          membership_package_id: ctx.monthly.id,
          package_name_snapshot: ctx.monthly.name,
          price_cents_snapshot: 7_000,
          currency: "EUR",
          source: "member",
          requested_by_id: ctx.member.id,
          hold_until: Date.add(gym_today(), -1),
          today: Date.add(gym_today(), -15)
        })
      end)

    assert desk_queue(conn, ctx) == []
    assert PackageRequests.mine(Map.put(ctx.context, :user_id, ctx.member.id)) == []

    assert %{"code" => "package_request_closed"} =
             conn |> collect(ctx, old.id) |> json_response(409)

    assert LapsePackageRequestsJob.run(%{organization_id: ctx.organization.id}) == 1

    lapsed =
      PackageRequestStore.with_tenant_context(ctx.context, fn ->
        PackageRequestStore.get(old.id)
      end)

    assert lapsed.status == "lapsed"

    # A new request can be made for the same package.
    assert conn |> ask(ctx, ctx.monthly) |> json_response(201)
  end

  defp tenant_fixture(user, name) do
    {:ok, organization} =
      Organizations.create_organization(%{name: "#{name} #{System.unique_integer([:positive])}"})

    add_tenant_member(organization, user, :owner)
    {:ok, context} = Organizations.resolve_tenant_context(user, organization.slug)
    {organization, context}
  end

  defp add_tenant_member(organization, user, role) do
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
