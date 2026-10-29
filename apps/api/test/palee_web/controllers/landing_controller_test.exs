defmodule PaleeWeb.LandingControllerTest do
  use PaleeWeb.ConnCase, async: false

  import Palee.TestFixtures

  alias Palee.Execution
  alias Palee.Finance
  alias Palee.Gamification
  alias Palee.Gamification.GamificationStore
  alias Palee.Organizations

  test "shows the landing payload and updates leaderboard opt-in", %{conn: conn} do
    athlete = user_fixture(%{role: :athlete})
    admin = admin_fixture()
    {:ok, organization} = Organizations.create_organization(%{name: "Landing Gym"})

    for {user, role} <- [{admin, :owner}, {athlete, :member}] do
      {:ok, _membership} =
        Organizations.add_membership(%{
          organization_id: organization.id,
          user_id: user.id,
          role: role,
          status: :active,
          joined_at: DateTime.utc_now()
        })
    end

    Palee.Repo.query!("SELECT set_config($1, $2, false)", [
      "app.organization_id",
      organization.id
    ])

    Palee.Repo.query!("SELECT set_config($1, $2, false)", ["app.user_id", athlete.id])

    workout = workout_fixture(admin)
    section_id = workout.sections |> List.first() |> Map.fetch!(:id)

    {:ok, _settings} =
      Gamification.update_settings(%{
        streak_shields: 3,
        streak_shield_reset_day: 7,
        leaderboard_enabled: true
      })

    {:ok, execution} =
      Execution.start_execution(athlete.id, %{
        # Server-derived in production (F-03); the history reads the workout
        # in this organization (ADR-133).
        organization_id: organization.id,
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

    # ADR-274: paid outside a charge in this test.
    {:ok, _subscription} =
      Finance.assign_package(membership.id, package.id, %{
        starts_on: Date.utc_today(),
        charge_now: false
      })

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
      |> get("/api/org/#{organization.slug}/landing")
      |> json_response(200)

    assert get_in(landing, ["gamification", "stats", "current_streak"]) == 1
    assert get_in(landing, ["gamification", "settings", "streak_shields"]) == 3
    refute Map.has_key?(get_in(landing, ["gamification", "settings"]), "weekly_workout_target")
    # ADR-229: the weekly goal is the person's own, the default until set.
    assert %{"weekly_workout_target" => 2, "is_default" => true} =
             get_in(landing, ["gamification", "goal"])

    assert get_in(landing, ["gamification", "settings", "streak_shield_reset_day"]) == 7
    assert get_in(landing, ["gamification", "settings", "leaderboard_enabled"]) == true
    refute Map.has_key?(get_in(landing, ["gamification", "settings"]), "theme_slug")
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
      |> post(
        "/api/org/#{organization.slug}/landing/leaderboard-opt-in",
        Jason.encode!(%{opted_in: true})
      )
      |> json_response(200)

    assert preference["opted_in"] == true
    # TD-092: the opt-in is stored in the gym and the (definer-refreshed)
    # leaderboard immediately lists the member.
    assert preference["visible"] == true
    assert Enum.any?(preference["weekly"], &(&1["user_id"] == athlete.id))

    updated_preference =
      conn
      |> recycle()
      |> put_bearer_token(athlete)
      |> put_req_header("content-type", "application/json")
      |> put_req_header("accept", "application/json")
      |> post(
        "/api/org/#{organization.slug}/landing/leaderboard-opt-in",
        Jason.encode!(%{opted_in: false})
      )
      |> json_response(200)

    assert updated_preference["opted_in"] == false
    assert updated_preference["visible"] == false
  end
end
