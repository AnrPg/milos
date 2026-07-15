defmodule MilosTrainingWeb.LandingControllerTest do
  use MilosTrainingWeb.ConnCase, async: false

  import MilosTraining.TestFixtures

  alias MilosTraining.Execution
  alias MilosTraining.Finance
  alias MilosTraining.Gamification
  alias MilosTraining.Gamification.GamificationStore

  test "shows the landing payload and updates leaderboard opt-in", %{conn: conn} do
    athlete = user_fixture(%{role: :athlete})
    admin = admin_fixture()
    workout = workout_fixture(admin)
    section_id = workout.sections |> List.first() |> Map.fetch!(:id)

    {:ok, _settings} =
      Gamification.update_settings(%{
        weekly_workout_target: 3,
        streak_shield_reset_day: 7,
        leaderboard_enabled: true,
        theme_slug: "sage"
      })

    {:ok, execution} =
      Execution.start_execution(athlete.id, %{
        master_workout_id: workout.id,
        source: :self_selected
      })

    {:ok, _completed_execution} =
      Execution.complete_execution(execution.id, athlete.id, %{
        completed_at_tz: "Europe/Athens",
        section_scores: [
          %{
            section_id: section_id,
            score_type: "reps",
            value: "30",
            unit: "reps"
          }
        ]
      })

    {:ok, _stats} =
      GamificationStore.upsert_user_stats(%{
        user_id: athlete.id,
        current_streak: 1,
        longest_streak: 1,
        total_workouts: 2,
        total_prs: 0,
        current_streak_shields: 1,
        last_workout_at: DateTime.utc_now(),
        consistency_score: 25.0,
        updated_at: DateTime.utc_now()
      })

    {:ok, _achievement} =
      GamificationStore.create_achievement(%{
        user_id: athlete.id,
        badge_key: "workouts_1",
        earned_at: DateTime.utc_now()
      })

    {:ok, package} =
      Finance.create_package(%{
        code: "landing_package",
        name: "Landing Package",
        family: "personal-programming",
        billing_period: "monthly",
        base_price_cents: 12_000
      })

    {:ok, membership} =
      Finance.upsert_membership(athlete.id, %{
        user_type_snapshot: "athlete",
        status: "active",
        signup_source: "direct",
        expires_on: Date.add(Date.utc_today(), 30),
        notes: "Remote coaching"
      })

    {:ok, _subscription} =
      Finance.assign_package(membership.id, package.id, %{starts_on: Date.utc_today()})

    {:ok, _payment} =
      Finance.record_payment(membership.id, %{
        amount_cents: 12_000,
        payment_method: "cash",
        payment_status: "paid",
        paid_on: Date.utc_today()
      })

    landing =
      conn
      |> put_bearer_token(athlete)
      |> get("/api/landing")
      |> json_response(200)

    assert get_in(landing, ["gamification", "stats", "current_streak"]) == 1
    assert get_in(landing, ["gamification", "settings", "weekly_workout_target"]) == 3
    assert get_in(landing, ["gamification", "settings", "streak_shield_reset_day"]) == 7
    assert get_in(landing, ["gamification", "settings", "leaderboard_enabled"]) == true
    assert get_in(landing, ["gamification", "settings", "theme_slug"]) == "sage"
    assert get_in(landing, ["gamification", "leaderboard", "visible"]) == false
    assert get_in(landing, ["membership", "package_name"]) == "Landing Package"
    assert get_in(landing, ["membership", "entitlement_status"]) == "active"
    assert get_in(landing, ["membership", "amount"]) == 12_000
    assert length(get_in(landing, ["gamification", "badges"])) == 1
    assert get_in(landing, ["recent_executions", Access.at(0), "workout_title"]) == workout.title

    assert get_in(landing, [
             "recent_executions",
             Access.at(0),
             "section_scores",
             Access.at(0),
             "section_name"
           ]) ==
             "Main Set"

    preference =
      conn
      |> put_bearer_token(athlete)
      |> put_req_header("content-type", "application/json")
      |> put_req_header("accept", "application/json")
      |> post("/api/landing/leaderboard-opt-in", Jason.encode!(%{opted_in: true}))
      |> json_response(200)

    assert preference["opted_in"] == true
    assert is_boolean(preference["visible"])

    updated_preference =
      conn
      |> recycle()
      |> put_bearer_token(athlete)
      |> put_req_header("content-type", "application/json")
      |> put_req_header("accept", "application/json")
      |> post("/api/landing/leaderboard-opt-in", Jason.encode!(%{opted_in: false}))
      |> json_response(200)

    assert updated_preference["opted_in"] == false
    assert updated_preference["visible"] == false
  end
end
