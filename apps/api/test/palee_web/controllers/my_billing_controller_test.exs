defmodule PaleeWeb.MyBillingControllerTest do
  @moduledoc """
  Εγώ › Πληρωμές over HTTP: one section per provider the person is a client
  of, never a staff-only membership or a business in demo mode (ADR-184).
  """

  use PaleeWeb.ConnCase, async: false

  import Palee.TestFixtures

  alias Palee.Application.{PublishBoxPublicProfile, UpdateBoxPublicProfile}
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

    # ADR-274: the test writes its own invoice for the period.
    {:ok, subscription} =
      Finance.assign_package(staff, membership.id, package.id, %{charge_now: false})

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

    # ADR-220: a renewing package leaves renewal to the member, on by default.
    assert [
             %{
               "id" => subscription_id,
               "current" => true,
               "package_name" => "12 visits",
               "auto_renew" => true,
               "can_change_auto_renew" => true
             }
           ] = box["subscriptions"]

    assert subscription_id == subscription.id

    assert [%{"balance_due_cents" => 4_000, "document_kind" => "invoice", "status" => "issued"}] =
             box["invoices"]

    assert box["actions"] == %{
             "self_service_purchase" => false,
             "self_service_cancel_auto_renew" => true,
             "self_service_leave" => true,
             "download_invoices" => true
           }

    assert box["membership"]["leaving_on"] == nil
    assert box["membership"]["leave_preview_on"]

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

  test "transactions merge invoices with lines, payments and events at any host", ctx do
    start_supervised!(
      {Oban, Keyword.put(Application.fetch_env!(:palee, Oban), :testing, :manual)}
    )

    {:ok, staff} = Organizations.resolve_tenant_context(ctx.owner, ctx.box.slug)

    {:ok, membership} =
      Finance.upsert_membership(staff, ctx.member.id, %{
        user_type_snapshot: "member",
        status: "active",
        signup_source: "direct"
      })

    {:ok, invoice} =
      Finance.create_invoice(staff, membership.id, %{
        amount_cents: 2_500,
        description: "Protein bar box",
        due_date: Date.add(Date.utc_today(), 7)
      })

    {:ok, _issued} = Finance.issue_invoice(staff, invoice.id, %{})

    {:ok, _payment} =
      Finance.record_payment(staff, membership.id, %{
        amount_cents: 2_500,
        currency: "EUR",
        paid_on: Date.utc_today(),
        payment_method: "cash",
        payment_status: "paid"
      })

    # An event at a box the member is not a client of, paid and part refunded.
    host = published_box!("Other Box")
    event = paid_event!(ctx.conn, host)
    base = "/api/org/#{host.organization.slug}/admin/community/events/#{event["id"]}"

    ctx.conn
    |> authed(ctx.member)
    |> send_json(:put, "/api/me/events/#{event["id"]}/rsvp", %{going: true})
    |> json_response(200)

    ctx.conn
    |> authed(host.owner)
    |> send_json(:put, "#{base}/attendees/#{ctx.member.id}/paid", %{payment_method: "cash"})
    |> json_response(200)

    ctx.conn
    |> authed(host.owner)
    |> send_json(:put, "#{base}/attendees/#{ctx.member.id}/refund", %{amount_cents: 500})
    |> json_response(200)

    feed =
      ctx.conn |> authed(ctx.member) |> get("/api/me/billing/transactions") |> json_response(200)

    kinds = Enum.map(feed["transactions"], & &1["kind"])
    assert Enum.sort(kinds) == Enum.sort(~w(invoice payment event_payment event_refund))
    assert feed["total"] == 4
    assert feed["partial"] == false

    invoice_entry = Enum.find(feed["transactions"], &(&1["kind"] == "invoice"))
    assert invoice_entry["counterparty"]["name"] == "Box Kypseli"

    assert [%{"description" => "Protein bar box", "total_cents" => 2_500}] =
             invoice_entry["details"]["lines"]

    refund = Enum.find(feed["transactions"], &(&1["kind"] == "event_refund"))
    assert refund["amount_cents"] == -500
    assert refund["title"] == "Open WOD"
    assert refund["counterparty"]["name"] =~ "Other Box"

    # Scoped to the coach: the box's own entries go, the other host's event stays.
    scoped =
      ctx.conn
      |> authed(ctx.member)
      |> get("/api/me/billing/transactions?organization_id=#{ctx.coach_org.id}")
      |> json_response(200)

    assert scoped["transactions"] |> Enum.map(& &1["kind"]) |> Enum.sort() ==
             ~w(event_payment event_refund)

    # Cursor pages walk the whole feed once.
    first =
      ctx.conn
      |> authed(ctx.member)
      |> get("/api/me/billing/transactions?limit=3")
      |> json_response(200)

    assert length(first["transactions"]) == 3
    assert first["next_cursor"]

    second =
      ctx.conn
      |> authed(ctx.member)
      |> get("/api/me/billing/transactions?limit=3&cursor=#{first["next_cursor"]}")
      |> json_response(200)

    assert length(second["transactions"]) == 1
    assert second["next_cursor"] == nil

    assert Enum.map(first["transactions"] ++ second["transactions"], & &1["id"]) ==
             Enum.map(feed["transactions"], & &1["id"])

    only =
      ctx.conn
      |> authed(ctx.member)
      |> get("/api/me/billing/transactions?kind=invoice")
      |> json_response(200)

    assert [%{"kind" => "invoice"}] = only["transactions"]

    assert %{"code" => "invalid_cursor"} =
             ctx.conn
             |> authed(ctx.member)
             |> get("/api/me/billing/transactions?cursor=nope")
             |> json_response(400)
  end

  test "member-visible campaign codes are offered; perks stay empty", ctx do
    {:ok, staff} = Organizations.resolve_tenant_context(ctx.owner, ctx.box.slug)

    {:ok, campaign} =
      Finance.create_promotion_campaign(staff, %{
        name: "Autumn welcome",
        starts_on: Date.add(Date.utc_today(), -1),
        ends_on: Date.add(Date.utc_today(), 30),
        params: %{"member_visible" => true}
      })

    {:ok, _code} =
      Finance.create_promotion_code(staff, campaign.id, %{
        code: "AUTUMN20",
        discount_type: "percent",
        discount_value: 20
      })

    {:ok, hidden} =
      Finance.create_promotion_campaign(staff, %{name: "Staff only", starts_on: Date.utc_today()})

    {:ok, _code} =
      Finance.create_promotion_code(staff, hidden.id, %{
        code: "SECRET",
        discount_type: "percent",
        discount_value: 50
      })

    body = ctx.conn |> authed(ctx.member) |> get("/api/me/billing") |> json_response(200)
    box = Enum.find(body["providers"], &(&1["organization_id"] == ctx.box.id))

    assert [%{"code" => "AUTUMN20", "campaign_name" => "Autumn welcome", "discount_value" => 20}] =
             box["available_offers"]

    assert box["perks"] == []
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

  defp send_json(conn, method, path, body) do
    conn
    |> put_req_header("content-type", "application/json")
    |> dispatch(@endpoint, method, path, Jason.encode!(body))
  end

  defp published_box!(name) do
    organization = org!(name)
    owner = user_fixture()
    add!(organization, owner, [:owner])
    {:ok, owner_context} = Organizations.resolve_tenant_context(owner, organization.slug)

    {:ok, profile} =
      UpdateBoxPublicProfile.call(owner_context, %{
        "about" => "Έλα να γνωριστούμε.",
        "disciplines" => ["crossfit"]
      })

    {:ok, _profile} =
      PublishBoxPublicProfile.publish(owner_context, %{"lock_version" => profile.lock_version})

    %{organization: organization, owner: owner}
  end

  defp paid_event!(conn, host) do
    starts = DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.add(2, :day)

    conn
    |> authed(host.owner)
    |> send_json(:post, "/api/me/events", %{
      host: host.organization.id,
      title: "Open WOD",
      starts_at: DateTime.to_iso8601(starts),
      ends_at: starts |> DateTime.add(1, :hour) |> DateTime.to_iso8601(),
      place_name: "Το box",
      audience: "open",
      price_cents: 1500
    })
    |> json_response(201)
    |> Map.fetch!("event")
  end
end
