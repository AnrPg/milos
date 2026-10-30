defmodule PaleeWeb.SoldOnlineControllerTest do
  @moduledoc """
  ADR-271 end to end with the sandbox provider: connecting online payments
  puts the paid packages on sale online once and tells the owner; the
  owner's «off» is never undone; packages say why members do not see them.
  """
  use PaleeWeb.ConnCase, async: false

  alias Palee.{Finance, Organizations}

  import Palee.TestFixtures

  setup do
    owner = admin_fixture(%{nickname: "sold_online_owner"})

    {:ok, organization} =
      Organizations.create_organization(%{
        name: "Sold Online Tenant #{System.unique_integer([:positive])}"
      })

    add_tenant_member(organization, owner, :owner)
    {:ok, context} = Organizations.resolve_tenant_context(owner, organization.slug)

    package = fn name, cents, extra ->
      {:ok, package} =
        Finance.create_package(
          context,
          Map.merge(
            %{
              name: name,
              family: "unlimited",
              billing_period: "monthly",
              base_price_cents: cents
            },
            extra
          )
        )

      package
    end

    %{
      owner: owner,
      organization: organization,
      context: context,
      unlimited: package.("Unlimited", 7_500, %{}),
      three: package.("3 φορές την εβδομάδα", 6_000, %{}),
      free: package.("Δοκιμαστικό", 0, %{}),
      retired: package.("Παλιό", 5_000, %{active: false})
    }
  end

  defp admin_path(ctx, path), do: "/api/org/#{ctx.organization.slug}/admin#{path}"
  defp as_owner(conn, ctx), do: put_bearer_token(conn, ctx.owner)

  defp connect_provider(conn, ctx) do
    conn
    |> as_owner(ctx)
    |> put(admin_path(ctx, "/payments/account"), %{provider: "sandbox", environment: "test"})
    |> json_response(200)
  end

  defp disconnect(conn, ctx) do
    conn |> as_owner(ctx) |> delete(admin_path(ctx, "/payments/account")) |> json_response(200)
  end

  defp set_sold_online(conn, ctx, package, value) do
    conn
    |> as_owner(ctx)
    |> patch(admin_path(ctx, "/finance/packages/#{package.id}"), %{sold_online: value})
    |> json_response(200)
    |> Map.fetch!("package")
  end

  defp packages(conn, ctx) do
    conn
    |> as_owner(ctx)
    |> get(admin_path(ctx, "/finance/packages"))
    |> json_response(200)
    |> Map.fetch!("packages")
    |> Map.new(&{&1["name"], {&1["sold_online"], &1["online_visibility"]}})
  end

  test "before connecting, packages are front-desk only and say so", %{conn: conn} = ctx do
    assert packages(conn, ctx) == %{
             "Unlimited" => {false, "off"},
             "3 φορές την εβδομάδα" => {false, "off"},
             "Δοκιμαστικό" => {false, "free"},
             "Παλιό" => {false, "inactive"}
           }

    package = set_sold_online(conn, ctx, ctx.unlimited, true)
    assert package["online_visibility"] == "no_provider"
  end

  test "connecting opens the paid packages once and tells the owner", %{conn: conn} = ctx do
    status = connect_provider(conn, ctx)

    assert %{"count" => 2, "opened_at" => _at} = status["account"]["packages_notice"]
    assert status["online_sales"] == %{"sold_online" => 2, "packages" => 2}

    assert packages(conn, ctx) == %{
             "Unlimited" => {true, "visible"},
             "3 φορές την εβδομάδα" => {true, "visible"},
             "Δοκιμαστικό" => {false, "free"},
             "Παλιό" => {false, "inactive"}
           }

    dismissed =
      conn
      |> as_owner(ctx)
      |> delete(admin_path(ctx, "/payments/account/packages-notice"))
      |> json_response(200)

    assert dismissed["account"]["packages_notice"] == nil
  end

  test "the owner's «off» is never switched back on", %{conn: conn} = ctx do
    off = set_sold_online(conn, ctx, ctx.three, false)
    assert off["online_visibility"] == "off"

    connect_provider(conn, ctx)
    assert packages(conn, ctx)["3 φορές την εβδομάδα"] == {false, "off"}

    # Switched off after connecting, then a reconnect: still off.
    set_sold_online(conn, ctx, ctx.unlimited, false)
    disconnect(conn, ctx)
    status = connect_provider(conn, ctx)

    assert packages(conn, ctx)["Unlimited"] == {false, "off"}
    assert status["online_sales"] == %{"sold_online" => 0, "packages" => 2}
  end

  test "a paid package created after connecting starts sold online", %{conn: conn} = ctx do
    connect_provider(conn, ctx)

    create = fn body ->
      conn
      |> as_owner(ctx)
      |> post(admin_path(ctx, "/finance/packages"), body)
      |> json_response(201)
      |> Map.fetch!("package")
    end

    paid = create.(%{name: "12 επισκέψεις", package_type: "membership", base_price_cents: 9_000})
    assert {paid["sold_online"], paid["online_visibility"]} == {true, "visible"}

    free = create.(%{name: "Δωρεάν", package_type: "membership", base_price_cents: 0})
    assert {free["sold_online"], free["online_visibility"]} == {false, "free"}

    chosen =
      create.(%{
        name: "Μόνο υποδοχή",
        package_type: "membership",
        base_price_cents: 5_000,
        sold_online: false
      })

    assert {chosen["sold_online"], chosen["online_visibility"]} == {false, "off"}
  end

  test "a purpose switched off in «Τι πληρώνεται online» hides the package",
       %{conn: conn} = ctx do
    connect_provider(conn, ctx)

    conn
    |> as_owner(ctx)
    |> put(admin_path(ctx, "/payments/account/options"), %{purposes: %{packages: false}})
    |> json_response(200)

    package =
      conn
      |> as_owner(ctx)
      |> get(admin_path(ctx, "/finance/packages/#{ctx.unlimited.id}"))
      |> json_response(200)
      |> Map.fetch!("package")

    assert {package["sold_online"], package["online_visibility"]} == {true, "purpose_off"}
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
