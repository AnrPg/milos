defmodule PaleeWeb.AdminShopReportControllerTest do
  use PaleeWeb.ConnCase, async: false

  alias Palee.{Organizations, Repo}
  alias Palee.TestSupport.ShopReportFixtures, as: F

  import Palee.TestFixtures

  setup do
    owner = admin_fixture()
    {:ok, organization} = Organizations.create_organization(%{name: "Shop Reports Gym"})

    {:ok, _membership} =
      Organizations.add_membership(%{
        organization_id: organization.id,
        user_id: owner.id,
        role: :owner,
        status: :active,
        joined_at: DateTime.utc_now()
      })

    Repo.query!("SELECT set_config($1, $2, false)", ["app.organization_id", organization.id])
    Repo.query!("SELECT set_config($1, $2, false)", ["app.user_id", owner.id])

    product = F.product(organization.id)
    variant = F.variant(organization.id, product, %{price_cents: 1_000, cost_price_cents: 400})

    F.paid_order(organization.id, DateTime.utc_now(), [
      %{
        product_id: product,
        variant_id: variant,
        quantity: 2,
        unit_price_cents: 1_000,
        cost_price_cents: 400
      }
    ])

    %{owner: owner, organization: organization}
  end

  test "every report answers in its documented shape", %{
    conn: conn,
    owner: owner,
    organization: org
  } do
    base = "/api/org/#{org.slug}/admin/shop"
    conn = put_bearer_token(conn, owner)

    overview = conn |> get("#{base}/reports/overview", %{days: 7}) |> json_response(200)
    assert overview["kpis"]["net_cents"] == 2_000
    assert overview["kpis"]["margin_cents"] == 1_200
    assert overview["window"]["time_zone"]

    for report <- ~w(sales products margin channels inventory attribution pricing) do
      assert %{"window" => %{"from" => _}} =
               conn |> get("#{base}/reports/#{report}", %{days: 7}) |> json_response(200)
    end

    assert %{"ok" => true, "drift_cents" => 0} =
             conn |> get("#{base}/reports/reconciliation", %{days: 2}) |> json_response(200)

    assert %{"code" => "invalid_report_window"} =
             conn |> get("#{base}/reports/sales", %{days: 999}) |> json_response(422)

    targets =
      conn
      |> put("#{base}/pricing-targets", %{category: "gear", target_margin_bp: 4_500})
      |> json_response(200)

    assert %{"category" => "gear", "target_margin_bp" => 4_500} in targets["targets"]
  end

  test "staff without the analytics capability are refused", %{conn: conn, organization: org} do
    desk = user_fixture(%{role: :member})

    {:ok, _membership} =
      Organizations.add_membership(%{
        organization_id: org.id,
        user_id: desk.id,
        role: :front_desk,
        status: :active,
        joined_at: DateTime.utc_now()
      })

    conn
    |> put_bearer_token(desk)
    |> get("/api/org/#{org.slug}/admin/shop/reports/sales")
    |> json_response(403)
  end
end
