defmodule MilosTrainingWeb.AdminSettingsControllerTest do
  use MilosTrainingWeb.ConnCase, async: false

  import MilosTraining.TestFixtures

  test "admin can patch only the global theme", %{conn: conn} do
    admin = admin_fixture()

    payload =
      conn
      |> put_bearer_token(admin)
      |> patch("/api/admin/settings", %{gamification: %{theme_slug: "aurora"}})
      |> json_response(200)

    assert get_in(payload, ["gamification", "theme_slug"]) == "aurora"
    assert get_in(payload, ["gamification", "weekly_workout_target"]) == 2
    assert get_in(payload, ["gamification", "leaderboard_enabled"]) == true
    assert get_in(payload, ["notifications", "enabled"]) == false
  end

  test "admin can configure browser push service settings", %{conn: conn} do
    admin = admin_fixture()

    payload =
      conn
      |> put_bearer_token(admin)
      |> patch("/api/admin/settings", %{
        notifications: %{
          vapid_public_key: "public-key",
          vapid_private_key: "private-key",
          vapid_subject: "mailto:gym@example.test"
        }
      })
      |> json_response(200)

    assert get_in(payload, ["notifications", "enabled"]) == true
    assert get_in(payload, ["notifications", "vapid_public_key"]) == "public-key"
    assert get_in(payload, ["notifications", "vapid_private_key_configured"]) == true
    refute Map.has_key?(payload["notifications"], "vapid_private_key")

    push_config =
      conn
      |> put_bearer_token(admin)
      |> get("/api/notifications/push-config")
      |> json_response(200)

    assert push_config == %{"enabled" => true, "vapid_public_key" => "public-key"}
  end
end
