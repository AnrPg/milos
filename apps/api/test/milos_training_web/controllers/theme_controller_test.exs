defmodule MilosTrainingWeb.ThemeControllerTest do
  use MilosTrainingWeb.ConnCase, async: false

  alias MilosTraining.{Gamification, Organizations, Repo}

  test "shows the active public theme without authentication", %{conn: conn} do
    {:ok, legacy_organization} = Organizations.ensure_legacy_organization_for_migration()

    Repo.query!("SELECT set_config($1, $2, false)", [
      "app.organization_id",
      legacy_organization.id
    ])

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
