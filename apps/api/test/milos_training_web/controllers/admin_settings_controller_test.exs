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
  end
end
