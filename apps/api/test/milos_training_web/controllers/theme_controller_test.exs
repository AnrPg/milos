defmodule MilosTrainingWeb.ThemeControllerTest do
  use MilosTrainingWeb.ConnCase, async: false

  alias MilosTraining.Gamification

  test "shows the active public theme without authentication", %{conn: conn} do
    {:ok, _settings} =
      Gamification.update_settings(%{
        weekly_workout_target: 2,
        streak_shield_reset_day: nil,
        leaderboard_enabled: true,
        theme_slug: "steel"
      })

    payload =
      conn
      |> get("/api/theme")
      |> json_response(200)

    assert payload["theme_slug"] == "steel"
  end
end
