defmodule PaleeWeb.MyBillingControllerTest do
  @moduledoc """
  Εγώ › Πληρωμές over HTTP: one section per provider the person is a client
  of, never a staff-only membership or a business in demo mode (ADR-184).
  """

  use PaleeWeb.ConnCase, async: false

  import Palee.TestFixtures

  alias Palee.{Finance, Organizations, Repo}

  setup %{conn: conn} do
    owner = user_fixture()
    member = user_fixture()
    box = org!("Box Kypseli")
    coach_org = org!("Nikos PT")
    add!(box, owner, [:owner, :coach])
    add!(coach_org, owner, [:owner, :coach])
    add!(box, member, [:member])
    add!(coach_org, member, [:member])

    %{conn: conn, owner: owner, member: member, box: box, coach_org: coach_org}
  end

  defp authed(conn, user), do: conn |> recycle() |> put_bearer_token(user)

  test "a section per provider with packages, invoices and the balance due", ctx do
    {:ok, staff} = Organizations.resolve_tenant_context(ctx.owner, ctx.box.slug)

    {:ok, package} =
      Finance.create_package(staff, %{
        code: "visits-12",
        name: "12 visits",
        family: "limited",
        billing_period: "monthly",
        base_price_cents: 8_900
      })

    {:ok, membership} =
      Finance.upsert_membership(staff, ctx.member.id, %{
        user_type_snapshot: "member",
        status: "active",
        signup_source: "direct"
      })

    {:ok, subscription} = Finance.assign_package(staff, membership.id, package.id, %{})

    {:ok, invoice} =
      Finance.create_invoice(staff, membership.id, %{
        amount_cents: 4_000,
        description: "October",
        due_date: Date.add(Date.utc_today(), 7)
      })

    {:ok, _issued} = Finance.issue_invoice(staff, invoice.id, %{})

    body = ctx.conn |> authed(ctx.member) |> get("/api/me/billing") |> json_response(200)

    assert [box, coach] = body["providers"]
    assert {box["name"], coach["name"]} == {"Box Kypseli", "Nikos PT"}
    assert box["organization_id"] == ctx.box.id
    assert box["partial"] == false
    assert box["outstanding_cents"] == 4_000

    assert [%{"id" => subscription_id, "current" => true, "package_name" => "12 visits"}] =
             box["subscriptions"]

    assert subscription_id == subscription.id

    assert [%{"balance_due_cents" => 4_000, "document_kind" => "invoice", "status" => "issued"}] =
             box["invoices"]

    assert box["actions"] == %{
             "self_service_purchase" => false,
             "self_service_cancel_auto_renew" => false,
             "download_invoices" => true
           }

    assert box["referrals"]["invited"] == 0

    # The coach's section is there and empty: no finance profile yet.
    assert coach["subscriptions"] == []
    assert coach["invoices"] == []
    assert coach["outstanding_cents"] == 0
    assert coach["partial"] == false
  end

  test "staff-only memberships and demo businesses are not providers", ctx do
    staff_only = org!("Where I coach")
    demo = org!("Demo Box")
    add!(staff_only, ctx.member, [:coach])
    add!(demo, ctx.member, [:member])

    Repo.query!("UPDATE organizations SET activation = 'demo' WHERE id = $1", [
      Ecto.UUID.dump!(demo.id)
    ])

    body = ctx.conn |> authed(ctx.member) |> get("/api/me/billing") |> json_response(200)

    assert Enum.map(body["providers"], & &1["name"]) == ["Box Kypseli", "Nikos PT"]
  end

  test "a person without a provider gets no sections", ctx do
    loner = user_fixture()

    assert %{"providers" => []} =
             ctx.conn |> authed(loner) |> get("/api/me/billing") |> json_response(200)
  end

  test "needs a signed-in person", ctx do
    assert ctx.conn |> get("/api/me/billing") |> json_response(401)
  end

  defp org!(name) do
    {:ok, organization} =
      Organizations.create_organization(%{name: "#{name} #{System.unique_integer([:positive])}"})

    Repo.query!("UPDATE organizations SET name = $1 WHERE id = $2", [
      name,
      Ecto.UUID.dump!(organization.id)
    ])

    %{organization | name: name}
  end

  defp add!(organization, user, roles) do
    {:ok, _membership} =
      Organizations.add_membership(%{
        organization_id: organization.id,
        user_id: user.id,
        role: hd(roles),
        roles: roles,
        status: :active,
        joined_at: DateTime.utc_now()
      })
  end
end
