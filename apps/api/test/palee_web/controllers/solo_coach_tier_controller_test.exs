defmodule PaleeWeb.SoloCoachTierControllerTest do
  @moduledoc "ADR-170: self-serve coach practice, the plan card, staff seats and the platform console."
  use PaleeWeb.ConnCase, async: false

  import Palee.TestFixtures

  alias Palee.{Community, Organizations}

  setup %{conn: conn} do
    coach = user_fixture()
    vendor = user_fixture()
    {:ok, _vendor} = Organizations.grant_vendor(vendor.id)

    %{
      conn: conn,
      coach: coach,
      vendor: vendor,
      coach_conn: put_bearer_token(conn, coach),
      vendor_conn: put_bearer_token(conn, vendor)
    }
  end

  defp send_json(conn, method, path, body) do
    conn
    |> recycle()
    |> put_req_header("content-type", "application/json")
    |> dispatch(@endpoint, method, path, Jason.encode!(body))
  end

  defp open_practice(ctx, body \\ %{name: "Νίκος Παπαδόπουλος", timezone: "Europe/Athens"}) do
    ctx.coach_conn |> send_json(:post, "/api/coach-practices", body) |> json_response(201)
  end

  test "the public catalog shows the solo-coach tier with its placeholder price", %{conn: conn} do
    assert %{"plans" => [plan]} =
             conn |> get("/api/public/platform-plans?audience=coach") |> json_response(200)

    assert %{
             "code" => "solo_coach",
             "audience" => "coach",
             "price_status" => "placeholder",
             "trial_days" => 30,
             "limits" => %{"staff_seats" => 2, "active_clients" => 50}
           } = plan
  end

  test "an account opens one practice: coach kind, owner and coach, Team club, plan on trial",
       ctx do
    practice = open_practice(ctx)
    assert %{"provider_kind" => "coach", "slug" => slug, "id" => org_id} = practice

    assert [:owner, :coach] == Organizations.member_roles(org_id, ctx.coach.id)

    clubs = Community.list_clubs(%{organization_id: org_id, user_id: ctx.coach.id}, [org_id])
    assert Enum.any?(clubs, &(&1.kind == "gym" and &1.name == "Team Νίκος"))

    plan =
      ctx.coach_conn |> recycle() |> get("/api/org/#{slug}/admin/plan") |> json_response(200)

    assert %{
             "plan" => %{"code" => "solo_coach"},
             "status" => "trialing",
             "notice" => nil,
             "trial_days_left" => 30,
             "usage" => [
               %{"key" => "staff_seats", "used" => 1, "limit" => 2, "state" => "ok"},
               %{"key" => "active_clients", "used" => 0, "limit" => 50}
             ]
           } = plan

    assert %{"audience" => "coach", "steps" => steps} =
             ctx.coach_conn
             |> recycle()
             |> get("/api/org/#{slug}/admin/onboarding")
             |> json_response(200)

    assert ~w(timezone profile sessions packages team bootcamp invite tour) ==
             Enum.map(steps, & &1["id"])

    assert %{"code" => "coach_practice_exists"} =
             ctx.coach_conn
             |> send_json(:post, "/api/coach-practices", %{name: "Second practice"})
             |> json_response(409)
  end

  test "a staff seat beyond the plan is refused; clients never are", ctx do
    %{"slug" => slug} = open_practice(ctx, %{name: "Μαρία Κ.", team_name: "Team Μαρία"})
    path = "/api/org/#{slug}/invitations"

    assert ctx.coach_conn |> send_json(:post, path, %{role: "coach"}) |> json_response(201)

    assert %{"code" => "plan_limit_reached"} =
             ctx.coach_conn |> send_json(:post, path, %{role: "admin"}) |> json_response(409)

    assert ctx.coach_conn |> send_json(:post, path, %{role: "member"}) |> json_response(201)
  end

  test "vendors confirm prices and move an organization to another plan; nobody else can", ctx do
    %{"id" => org_id, "slug" => slug} = open_practice(ctx)

    assert ctx.coach_conn
           |> send_json(:patch, "/api/platform/plans/solo_coach", %{monthly_price_cents: 0})
           |> json_response(403)

    assert %{"monthly_price_cents" => 2400, "price_status" => "confirmed", "code" => "solo_coach"} =
             ctx.vendor_conn
             |> send_json(:patch, "/api/platform/plans/solo_coach", %{
               monthly_price_cents: 2400,
               price_status: "confirmed",
               code: "renamed"
             })
             |> json_response(200)

    assert ctx.vendor_conn
           |> send_json(:patch, "/api/platform/plans/solo_coach", %{limits: %{staff_seats: 0}})
           |> json_response(422)

    assert %{"code" => "studio", "is_default" => false} =
             ctx.vendor_conn
             |> send_json(:post, "/api/platform/plans", %{
               code: "studio",
               audience: "coach",
               name: "Studio",
               limits: %{staff_seats: 5},
               monthly_price_cents: 4900
             })
             |> json_response(201)

    assert %{"plan_code" => "studio", "status" => "comped", "price_override_cents" => 0} =
             ctx.vendor_conn
             |> send_json(:put, "/api/platform/organizations/#{org_id}/plan", %{
               plan_code: "studio",
               status: "comped",
               price_override_cents: 0
             })
             |> json_response(200)

    assert %{"code" => "trial_end_required"} =
             ctx.vendor_conn
             |> send_json(:put, "/api/platform/organizations/#{org_id}/plan", %{
               plan_code: "studio",
               status: "trialing"
             })
             |> json_response(422)

    assert %{"code" => "unknown_plan"} =
             ctx.vendor_conn
             |> send_json(:put, "/api/platform/organizations/#{org_id}/plan", %{
               plan_code: "nope",
               status: "active"
             })
             |> json_response(422)

    assert %{"subscriptions" => subscriptions} =
             ctx.vendor_conn
             |> recycle()
             |> get("/api/platform/subscriptions")
             |> json_response(200)

    assert Enum.any?(
             subscriptions,
             &(&1["organization_id"] == org_id and &1["plan_code"] == "studio")
           )

    assert %{"plan" => %{"code" => "studio"}, "status" => "comped"} =
             ctx.coach_conn
             |> recycle()
             |> get("/api/org/#{slug}/admin/plan")
             |> json_response(200)

    assert ctx.coach_conn |> recycle() |> get("/api/platform/subscriptions") |> json_response(403)
  end
end
