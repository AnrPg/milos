defmodule PaleeWeb.ThemeControllerTest do
  use PaleeWeb.ConnCase, async: false

  alias Palee.{Gamification, Organizations}

  setup do
    {:ok, gym} = Organizations.create_organization(%{name: "Theme Gym"})

    {:ok, _settings} =
      Gamification.with_tenant_context(%{organization_id: gym.id}, fn ->
        Gamification.update_settings(%{
          weekly_workout_target: 2,
          streak_shield_reset_day: nil,
          leaderboard_enabled: true,
          theme_slug: "steel"
        })
      end)

    %{gym: gym}
  end

  # TD-092: the request has no tenant scope; the gym is named by the slug the
  # web client sends with every request.
  test "shows the gym's public theme without authentication", %{conn: conn, gym: gym} do
    payload =
      conn
      |> put_req_header("x-organization-slug", gym.slug)
      |> get("/api/theme")
      |> json_response(200)

    assert payload["theme_slug"] == "steel"
  end

  test "falls back to the default theme without a known gym", %{conn: conn} do
    assert %{"theme_slug" => "frost"} = conn |> get("/api/theme") |> json_response(200)

    assert %{"theme_slug" => "frost"} =
             conn
             |> put_req_header("x-organization-slug", "no-such-gym")
             |> get("/api/theme")
             |> json_response(200)
  end
end
