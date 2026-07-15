defmodule MilosTrainingWeb.AdminChallengeControllerTest do
  use MilosTrainingWeb.ConnCase, async: false

  import MilosTraining.TestFixtures

  test "admin can create and list seasonal challenges", %{conn: conn} do
    admin = admin_fixture()
    authed = put_bearer_token(conn, admin)

    created =
      authed
      |> post_json("/api/admin/challenges", %{
        title: "Streak Week",
        description: "Hit two sessions",
        criteria_type: "workout_count",
        criteria_value: %{count: 2},
        badge_key: "challenge_streak_week",
        badge_label: "Streak Week",
        starts_at: Date.to_iso8601(Date.utc_today()),
        ends_at: Date.to_iso8601(Date.add(Date.utc_today(), 7))
      })
      |> json_response(201)

    assert get_in(created, ["challenge", "title"]) == "Streak Week"

    listing =
      authed
      |> recycle()
      |> get("/api/admin/challenges")
      |> json_response(200)

    assert Enum.any?(listing["challenges"], &(&1["badge_key"] == "challenge_streak_week"))
  end

  test "rejects a fourth overlapping active challenge", %{conn: conn} do
    admin = admin_fixture()
    authed = put_bearer_token(conn, admin)

    for idx <- 1..3 do
      authed
      |> recycle()
      |> put_bearer_token(admin)
      |> post_json("/api/admin/challenges", %{
        title: "Challenge #{idx}",
        criteria_type: "workout_count",
        criteria_value: %{count: 2},
        badge_key: "challenge_overlap_#{idx}",
        badge_label: "Overlap #{idx}",
        starts_at: Date.to_iso8601(Date.utc_today()),
        ends_at: Date.to_iso8601(Date.add(Date.utc_today(), 7))
      })
      |> json_response(201)
    end

    response =
      authed
      |> recycle()
      |> put_bearer_token(admin)
      |> post_json("/api/admin/challenges", %{
        title: "Too Many",
        criteria_type: "workout_count",
        criteria_value: %{count: 2},
        badge_key: "challenge_overlap_limit",
        badge_label: "Too Many",
        starts_at: Date.to_iso8601(Date.utc_today()),
        ends_at: Date.to_iso8601(Date.add(Date.utc_today(), 7))
      })
      |> json_response(422)

    assert response["error"] =~ "maximum of 3"
  end

  test "allows ranges that overlap three challenges without exceeding three concurrently", %{
    conn: conn
  } do
    admin = admin_fixture()
    authed = put_bearer_token(conn, admin)

    [
      {"A", ~D[2026-06-01], ~D[2026-06-05]},
      {"B", ~D[2026-06-04], ~D[2026-06-08]},
      {"C", ~D[2026-06-07], ~D[2026-06-11]}
    ]
    |> Enum.each(fn {suffix, starts_at, ends_at} ->
      authed
      |> recycle()
      |> put_bearer_token(admin)
      |> post_json("/api/admin/challenges", %{
        title: "Challenge #{suffix}",
        criteria_type: "workout_count",
        criteria_value: %{count: 2},
        badge_key: "challenge_chain_#{suffix}",
        badge_label: "Chain #{suffix}",
        starts_at: Date.to_iso8601(starts_at),
        ends_at: Date.to_iso8601(ends_at)
      })
      |> json_response(201)
    end)

    response =
      authed
      |> recycle()
      |> put_bearer_token(admin)
      |> post_json("/api/admin/challenges", %{
        title: "Bridge",
        criteria_type: "workout_count",
        criteria_value: %{count: 2},
        badge_key: "challenge_chain_bridge",
        badge_label: "Bridge",
        starts_at: "2026-06-02",
        ends_at: "2026-06-10"
      })
      |> json_response(201)

    assert get_in(response, ["challenge", "badge_key"]) == "challenge_chain_bridge"
  end

  defp post_json(conn, path, payload) do
    conn
    |> Plug.Conn.delete_req_header("content-type")
    |> Plug.Conn.put_req_header("content-type", "application/json")
    |> post(path, Jason.encode!(payload))
  end
end
