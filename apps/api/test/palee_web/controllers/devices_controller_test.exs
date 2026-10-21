defmodule PaleeWeb.DevicesControllerTest do
  use PaleeWeb.ConnCase, async: false

  import Palee.TestFixtures

  alias Palee.{FakeGarminClient, Organizations, Repo}
  alias Palee.Execution.TrainingLogEntry

  setup %{conn: conn} do
    on_exit(&FakeGarminClient.reset/0)
    user = user_fixture(%{role: :member})
    %{user: user, conn: put_bearer_token(conn, user)}
  end

  defp again(conn, user), do: conn |> recycle() |> put_bearer_token(user)

  defp garmin_row(conn, user) do
    conn
    |> again(user)
    |> get("/api/me/devices")
    |> json_response(200)
    |> Map.fetch!("integrations")
    |> Enum.find(&(&1["provider"] == "garmin"))
  end

  defp connect!(conn, user, body \\ %{health_data_consent: true, backfill_days: 0}) do
    %{"authorize_url" => url} =
      conn |> again(user) |> post("/api/me/devices/garmin/connect", body) |> json_response(200)

    %{"state" => state} = url |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query()

    location =
      build_conn()
      |> get("/api/integrations/garmin/callback", %{state: state, code: "code-1"})
      |> redirected_to(302)

    assert location =~ "/me/devices?garmin=connected"
    state
  end

  defp garmin_push(body, client_id \\ FakeGarminClient.client_id()) do
    build_conn()
    |> put_req_header("content-type", "application/json")
    |> then(&if(client_id, do: put_req_header(&1, "garmin-client-id", client_id), else: &1))
    |> post("/api/integrations/garmin/push", Jason.encode!(body))
  end

  defp run(id, start, minutes) do
    %{
      "userId" => "garmin-user-1",
      "summaryId" => id,
      "activityType" => "RUNNING",
      "startTimeInSeconds" => DateTime.to_unix(start),
      "durationInSeconds" => minutes * 60
    }
  end

  test "without Garmin credentials the row says «Σύντομα» and connecting is refused", %{
    conn: conn,
    user: user
  } do
    assert %{"status" => "unavailable", "configured" => false, "capability" => "not_configured"} =
             garmin_row(conn, user)

    assert %{"code" => "garmin_not_configured"} =
             conn
             |> again(user)
             |> post("/api/me/devices/garmin/connect", %{})
             |> json_response(503)

    assert %{"code" => "garmin_not_configured"} =
             garmin_push(%{"activities" => []}) |> json_response(503)
  end

  test "connect asks for the health consent, then signs in with PKCE and comes back", %{
    conn: conn,
    user: user
  } do
    FakeGarminClient.configure()
    assert %{"status" => "disconnected", "configured" => true} = garmin_row(conn, user)

    assert %{"code" => "health_data_consent_required"} =
             conn
             |> again(user)
             |> post("/api/me/devices/garmin/connect", %{backfill_days: 30})
             |> json_response(403)

    conn
    |> again(user)
    |> post("/api/me/devices/garmin/connect", %{backfill_days: 7, health_data_consent: true})
    |> json_response(422)

    state =
      connect!(conn, user, %{
        health_data_consent: true,
        backfill_days: 30,
        sync_prefs: %{sleep: false}
      })

    assert %{
             "status" => "connected",
             "connection" => %{
               "status" => "active",
               "backfill_status" => "done",
               "backfill_progress" => 100,
               "sync_prefs" => %{"sleep" => false, "activities" => true},
               "needs_reconnect" => false
             }
           } = garmin_row(conn, user)

    # A used state does not work twice.
    assert build_conn()
           |> get("/api/integrations/garmin/callback", %{state: state, code: "code-1"})
           |> redirected_to(302) =~ "garmin=error&reason=invalid_oauth_state"

    assert %{"code" => "device_already_connected"} =
             conn
             |> again(user)
             |> post("/api/me/devices/garmin/connect", %{})
             |> json_response(409)
  end

  test "workouts alone need no health consent; turning on health data does", %{
    conn: conn,
    user: user
  } do
    FakeGarminClient.configure()
    workouts_only = %{activities: true, sleep: false, weight: false, resting_hr: false}

    connect!(conn, user, %{backfill_days: 0, sync_prefs: workouts_only})

    assert %{"connection" => %{"sync_prefs" => %{"activities" => true, "sleep" => false}}} =
             garmin_row(conn, user)

    assert %{"code" => "health_data_consent_required"} =
             conn
             |> again(user)
             |> patch("/api/me/devices/garmin", %{sync_prefs: %{sleep: true}})
             |> json_response(403)

    assert %{"garmin" => %{"sync_prefs" => %{"sleep" => false, "activities" => false}}} =
             conn
             |> again(user)
             |> patch("/api/me/devices/garmin", %{sync_prefs: %{activities: false}})
             |> json_response(200)

    assert %{"garmin" => %{"sync_prefs" => %{"sleep" => true}}} =
             conn
             |> again(user)
             |> patch("/api/me/devices/garmin", %{
               sync_prefs: %{sleep: true},
               health_data_consent: true
             })
             |> json_response(200)

    # Once given, the consent covers later changes.
    assert %{"garmin" => %{"sync_prefs" => %{"weight" => true}}} =
             conn
             |> again(user)
             |> patch("/api/me/devices/garmin", %{sync_prefs: %{weight: true}})
             |> json_response(200)
  end

  test "Πρόοδος reads the member's own resting heart rate, labelled with its source", %{
    conn: conn,
    user: user
  } do
    FakeGarminClient.configure()

    assert %{"points" => [], "latest" => nil, "average" => nil, "range" => "3m"} =
             conn |> again(user) |> get("/api/me/daily-stats") |> json_response(200)

    connect!(conn, user)
    today = Date.utc_today()

    daily = fn id, days_ago, bpm ->
      %{
        "userId" => "garmin-user-1",
        "summaryId" => id,
        "calendarDate" => Date.to_iso8601(Date.add(today, -days_ago)),
        "restingHeartRateInBeatsPerMinute" => bpm
      }
    end

    garmin_push(%{
      "dailies" => [daily.("d-1", 1, 52), daily.("d-2", 0, 49), daily.("d-3", 60, 55)]
    })
    |> json_response(200)

    assert %{
             "metric" => "resting_hr",
             "range" => "1m",
             "points" => [
               %{"value" => 52, "source" => "garmin"},
               %{"value" => 49, "source" => "garmin"}
             ],
             "latest" => %{"value" => 49, "source" => "garmin"},
             "average" => 51,
             "sources" => ["garmin"]
           } =
             conn
             |> again(user)
             |> get("/api/me/daily-stats?metric=resting_hr&range=1m")
             |> json_response(200)

    assert %{"points" => points} =
             conn |> again(user) |> get("/api/me/daily-stats?range=3m") |> json_response(200)

    assert length(points) == 3

    # Someone else sees none of it.
    other = user_fixture(%{role: :member})

    assert %{"points" => []} =
             build_conn()
             |> put_bearer_token(other)
             |> get("/api/me/daily-stats")
             |> json_response(200)

    conn |> again(user) |> get("/api/me/daily-stats?range=5y") |> json_response(422)
    conn |> again(user) |> get("/api/me/daily-stats?metric=calories") |> json_response(422)
  end

  test "Garmin's refusal at sign-in comes back as an error", %{conn: conn, user: user} do
    FakeGarminClient.configure()

    %{"authorize_url" => url} =
      conn
      |> again(user)
      |> post("/api/me/devices/garmin/connect", %{health_data_consent: true})
      |> json_response(200)

    %{"state" => state} = url |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query()

    assert build_conn()
           |> get("/api/integrations/garmin/callback", %{state: state, error: "access_denied"})
           |> redirected_to(302) =~ "garmin=error&reason=garmin_access_denied"
  end

  test "pushes are verified, idempotent and show up on the journal's device card", %{
    conn: conn,
    user: user
  } do
    FakeGarminClient.configure()
    connect!(conn, user)

    body = %{"activities" => [run("r-1", ~U[2026-10-20 07:00:00Z], 30)]}
    assert %{"code" => "invalid_push"} = garmin_push(body, nil) |> json_response(401)
    assert %{"code" => "invalid_push"} = garmin_push(body, "someone-else") |> json_response(401)
    assert %{"queued" => 1} = garmin_push(body) |> json_response(200)
    assert %{"queued" => 1} = garmin_push(body) |> json_response(200)

    assert %{"visible" => true, "new_total" => 1, "new_counts" => %{"activity" => 1}} =
             conn |> again(user) |> get("/api/me/devices/summary") |> json_response(200)

    assert %{"visible" => false} =
             conn |> again(user) |> post("/api/me/devices/summary/seen") |> json_response(200)

    %{"items" => [item]} =
      conn
      |> again(user)
      |> get("/api/me/journal", %{kinds: "device_activity"})
      |> json_response(200)

    assert %{"kind" => "device_activity", "journal_visibility" => "private"} = item
    assert %{"sport" => "run", "duration_seconds" => 1800} = item["entry"]
  end

  test "prefs, sync now and disconnect keeping or deleting the data", %{conn: conn, user: user} do
    FakeGarminClient.configure()
    connect!(conn, user)

    assert %{"garmin" => %{"sync_prefs" => %{"weight" => false}}} =
             conn
             |> again(user)
             |> patch("/api/me/devices/garmin", %{sync_prefs: %{weight: false}})
             |> json_response(200)

    assert %{"code" => "invalid_sync_prefs"} =
             conn
             |> again(user)
             |> patch("/api/me/devices/garmin", %{sync_prefs: %{steps: true}})
             |> json_response(422)

    assert %{"garmin" => %{"status" => "connected"}} =
             conn |> again(user) |> post("/api/me/devices/garmin/sync") |> json_response(200)

    assert %{"code" => "sync_too_soon"} =
             conn |> again(user) |> post("/api/me/devices/garmin/sync") |> json_response(429)

    garmin_push(%{"activities" => [run("r-2", ~U[2026-10-20 07:00:00Z], 30)]})

    assert %{"status" => "revoked", "deleted" => nil} =
             conn |> again(user) |> delete("/api/me/devices/garmin") |> json_response(200)

    assert %{"status" => "disconnected"} = garmin_row(conn, user)

    connect!(conn, user)

    assert %{"deleted" => %{"activities" => 1}} =
             conn
             |> again(user)
             |> delete("/api/me/devices/garmin?delete_data=true")
             |> json_response(200)
  end

  test "a workout that could be two entries waits for the member's answer", %{
    conn: conn,
    user: user
  } do
    FakeGarminClient.configure()
    connect!(conn, user)
    {:ok, gym} = Organizations.create_organization(%{name: "Confirm Gym"})
    start = ~U[2026-10-20 18:00:00.000000Z]

    [first, _second] =
      for offset <- [0, 600] do
        Repo.insert!(%TrainingLogEntry{
          organization_id: gym.id,
          user_id: user.id,
          source_type: "freeform",
          title: "WOD",
          performed_at_utc: DateTime.add(start, offset),
          duration_seconds: 3600,
          idempotency_key: Ecto.UUID.generate(),
          journal_visibility: "private"
        })
      end

    garmin_push(%{"activities" => [run("r-3", DateTime.add(start, 300), 50)]})

    %{
      "imports" => [
        %{"id" => import_id, "activity" => %{"state" => "pending", "candidates" => [_, _]}}
      ]
    } =
      conn |> again(user) |> get("/api/me/devices/garmin/pending") |> json_response(200)

    assert %{"code" => "device_confirmation_required"} =
             conn
             |> again(user)
             |> post("/api/me/device-imports/#{import_id}/confirm", %{})
             |> json_response(422)

    assert %{"activity" => %{"state" => "merged"}} =
             conn
             |> again(user)
             |> post("/api/me/device-imports/#{import_id}/confirm", %{target_id: first.id})
             |> json_response(200)

    assert %{"imports" => []} =
             conn |> again(user) |> get("/api/me/devices/garmin/pending") |> json_response(200)
  end
end
