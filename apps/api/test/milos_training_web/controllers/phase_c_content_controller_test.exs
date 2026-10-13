defmodule MilosTrainingWeb.PhaseCContentControllerTest do
  use MilosTrainingWeb.ConnCase, async: false

  alias MilosTraining.{Finance, Organizations, Repo}
  alias MilosTraining.Analytics.Domain.ProgressStats

  import MilosTraining.TestFixtures

  setup %{conn: conn} do
    {:ok, organization} = Organizations.ensure_legacy_organization_for_migration()
    Repo.query!("SELECT set_config($1, $2, false)", ["app.organization_id", organization.id])

    admin = admin_fixture()
    {:ok, _} = Organizations.ensure_legacy_membership_for_migration(admin, :owner)

    {:ok, _settings} =
      Finance.update_finance_settings(%{
        entitlement_enforcement_mode: "enforce_managed",
        entitlement_timezone: "Europe/Athens",
        payment_reminder_interval_days: 7
      })

    %{
      admin_conn: put_bearer_token(conn, admin),
      base: "/api/org/#{Organizations.legacy_organization_slug()}"
    }
  end

  defp client(conn, fields) do
    user = user_fixture()
    {:ok, _} = Organizations.ensure_legacy_membership_for_migration(user)

    {:ok, membership} =
      Finance.upsert_membership(user.id, %{
        user_type_snapshot: "member",
        status: "active",
        signup_source: "direct"
      })

    {:ok, package} =
      Finance.create_package(%{
        name: "Content #{System.unique_integer([:positive])}",
        package_type: "membership",
        fields: fields
      })

    {:ok, _} = Finance.assign_package(membership.id, package.id, %{})
    put_bearer_token(conn, user)
  end

  defp send_json(conn, method, path, body) do
    conn
    |> recycle()
    |> put_req_header("content-type", "application/json")
    |> dispatch(@endpoint, method, path, Jason.encode!(body))
  end

  test "admins publish videos and only clients whose package includes them can watch", %{
    conn: conn,
    admin_conn: admin_conn,
    base: base
  } do
    assert %{"errors" => _} =
             admin_conn
             |> send_json(:post, "#{base}/admin/videos", %{
               title: "Mobility",
               video_url: "http://insecure.example/video"
             })
             |> json_response(422)

    video =
      admin_conn
      |> send_json(:post, "#{base}/admin/videos", %{
        title: "Hip mobility",
        video_url: "https://videos.example/hips",
        duration_minutes: 20,
        tags: [" Mobility ", "mobility", "Hips"]
      })
      |> json_response(201)
      |> Map.fetch!("video")

    assert video["tags"] == ["mobility", "hips"]
    assert video["published_at"] == nil

    viewer = client(conn, %{"content.on_demand_video" => true})

    assert %{"videos" => []} =
             viewer |> recycle() |> get("#{base}/me/videos") |> json_response(200)

    admin_conn
    |> send_json(:post, "#{base}/admin/videos/#{video["id"]}/publish", %{published: true})
    |> json_response(200)

    assert %{"videos" => [%{"title" => "Hip mobility"}]} =
             viewer |> recycle() |> get("#{base}/me/videos") |> json_response(200)

    outsider = client(conn, %{})
    assert outsider |> recycle() |> get("#{base}/me/videos") |> json_response(403)

    admin_conn
    |> send_json(:post, "#{base}/admin/videos/#{video["id"]}/archive", %{})
    |> json_response(200)

    assert %{"videos" => []} =
             viewer |> recycle() |> get("#{base}/me/videos") |> json_response(200)
  end

  test "advanced statistics need the package benefit", %{conn: conn, base: base} do
    analyst = client(conn, %{"content.advanced_analytics" => true})

    assert %{
             "progress" => %{
               "weekly" => weekly,
               "totals" => %{"sessions" => 0},
               "pr_timeline" => []
             }
           } =
             analyst |> recycle() |> get("#{base}/me/progress") |> json_response(200)

    assert length(weekly) == 12

    plain = client(conn, %{})
    assert plain |> recycle() |> get("#{base}/me/progress") |> json_response(403)
  end

  test "progress statistics track weeks, streaks and repeated section scores" do
    today = ~D[2026-10-14]
    workout = Ecto.UUID.generate()

    executions = [
      execution(workout, ~U[2026-10-13 08:00:00Z], 30, [%{"section_id" => "s1", "value" => 100}]),
      execution(workout, ~U[2026-10-06 08:00:00Z], 45, [%{"section_id" => "s1", "value" => 90}]),
      execution(Ecto.UUID.generate(), ~U[2026-09-29 08:00:00Z], 15, []),
      %{status: "active", completed_at_utc: nil}
    ]

    stats = ProgressStats.build(executions, today)

    assert stats.totals == %{sessions: 3, minutes: 90, workouts: 2}
    assert stats.consistency.current_streak_weeks == 3
    assert stats.consistency.active_weeks == 3
    assert [%{section_id: "s1", points: [%{value: 90}, %{value: 100}]}] = stats.score_history
    assert List.last(stats.weekly).sessions == 1
  end

  defp execution(workout_id, completed_at, minutes, scores) do
    %{
      id: Ecto.UUID.generate(),
      master_workout_id: workout_id,
      workout_title: "WOD",
      status: "completed",
      source: "repeat",
      completed_at_utc: completed_at,
      total_elapsed_ms: minutes * 60_000,
      section_scores: scores
    }
  end
end
