defmodule PaleeWeb.PhoneHealthControllerTest do
  use PaleeWeb.ConnCase, async: false

  import Palee.TestFixtures

  alias Palee.FakeGarminClient

  setup %{conn: conn} do
    on_exit(&FakeGarminClient.reset/0)
    user = user_fixture(%{role: :member})
    %{user: user, conn: put_bearer_token(conn, user)}
  end

  defp again(conn, user), do: conn |> recycle() |> put_bearer_token(user)

  defp row(conn, user, provider) do
    conn
    |> again(user)
    |> get("/api/me/devices")
    |> json_response(200)
    |> Map.fetch!("integrations")
    |> Enum.find(&(&1["provider"] == provider))
  end

  defp connect!(conn, user, provider \\ "apple_health", body \\ %{health_data_consent: true}) do
    conn
    |> again(user)
    |> post("/api/me/devices/phone/#{provider}/connect", body)
    |> json_response(200)
    |> Map.fetch!("row")
  end

  defp ingest(conn, user, body, provider \\ "apple_health") do
    conn |> again(user) |> post("/api/me/devices/phone/#{provider}/ingest", body)
  end

  defp workout(id, start, minutes, extra \\ %{}) do
    Map.merge(
      %{
        "id" => id,
        "type" => "RUNNING",
        "start" => DateTime.to_iso8601(start),
        "end" => DateTime.to_iso8601(DateTime.add(start, minutes * 60))
      },
      extra
    )
  end

  test "both phone rows say native_only until the app connects one", %{conn: conn, user: user} do
    assert %{"status" => "native_only", "connection" => nil, "history_days" => 30} =
             row(conn, user, "apple_health")

    assert %{"status" => "native_only", "sync_prefs" => %{"steps" => true}} =
             row(conn, user, "health_connect")

    assert %{"code" => "phone_health_not_connected"} =
             conn |> ingest(user, %{"activities" => []}) |> json_response(422)

    conn |> again(user) |> post("/api/me/devices/phone/garmin/connect", %{}) |> json_response(422)
  end

  test "connecting asks for the health consent unless only workouts come in", %{
    conn: conn,
    user: user
  } do
    assert %{"code" => "health_data_consent_required"} =
             conn
             |> again(user)
             |> post("/api/me/devices/phone/apple_health/connect", %{})
             |> json_response(403)

    workouts_only = %{
      activities: true,
      sleep: false,
      weight: false,
      resting_hr: false,
      steps: false
    }

    assert %{"status" => "connected", "connection" => connection} =
             connect!(conn, user, "apple_health", %{sync_prefs: workouts_only})

    assert %{"status" => "active", "last_synced_at" => nil, "read_from" => read_from} =
             connection

    {:ok, read_from, 0} = DateTime.from_iso8601(read_from)
    assert DateTime.diff(DateTime.utc_now(), read_from, :day) in 29..30

    assert %{"code" => "health_data_consent_required"} =
             conn
             |> again(user)
             |> patch("/api/me/devices/phone/apple_health", %{sync_prefs: %{steps: true}})
             |> json_response(403)

    assert %{"row" => %{"sync_prefs" => %{"steps" => true}}} =
             conn
             |> again(user)
             |> patch("/api/me/devices/phone/apple_health", %{
               sync_prefs: %{steps: true},
               health_data_consent: true
             })
             |> json_response(200)

    conn
    |> again(user)
    |> patch("/api/me/devices/phone/apple_health", %{sync_prefs: %{steps: "yes"}})
    |> json_response(422)

    # Connecting again keeps the link and only changes the choices.
    assert %{"connection" => %{"sync_prefs" => %{"sleep" => false}}} =
             connect!(conn, user, "apple_health", %{sync_prefs: workouts_only})
  end

  test "a batch lands in the journal, Ευεξία, Σώμα and Πρόοδος, once", %{conn: conn, user: user} do
    connect!(conn, user)
    today = Date.utc_today()
    start = DateTime.new!(Date.add(today, -1), ~T[06:00:00], "Etc/UTC")

    body = %{
      "activities" => [
        workout("hk-run-1", start, 42, %{"distance_m" => 7300.0, "avg_hr" => 151.4})
      ],
      "sleeps" => [
        %{
          "id" => Date.to_iso8601(Date.add(today, -1)),
          "start" => "#{Date.add(today, -2)}T23:10:00+03:00",
          "end" => "#{Date.add(today, -1)}T06:40:00+03:00"
        }
      ],
      "weights" => [
        %{"id" => "hk-w-1", "at" => "#{Date.add(today, -1)}T07:05:00+03:00", "kg" => 71.84}
      ],
      "dailies" => [
        %{"date" => Date.to_iso8601(Date.add(today, -1)), "resting_hr" => 54, "steps" => 9120},
        %{"date" => Date.to_iso8601(today), "steps" => 2300}
      ]
    }

    assert %{"counts" => %{"imported" => 6}, "row" => %{"connection" => connection}} =
             conn |> ingest(user, body) |> json_response(200)

    assert connection["last_synced_at"]

    # The same window again changes nothing.
    assert %{"counts" => %{"duplicate" => 6}} = conn |> ingest(user, body) |> json_response(200)

    %{"items" => [item]} =
      conn
      |> again(user)
      |> get("/api/me/journal", %{kinds: "device_activity"})
      |> json_response(200)

    assert %{"journal_visibility" => "private"} = item

    assert %{
             "provider" => "apple_health",
             "sport" => "run",
             "duration_seconds" => 2520,
             "avg_heart_rate" => 151,
             "started_tz" => "UTC"
           } = item["entry"]

    assert %{"points" => [%{"value" => 9120, "source" => "apple_health"}, %{"value" => 2300}]} =
             conn
             |> again(user)
             |> get("/api/me/daily-stats?metric=steps&range=1m")
             |> json_response(200)

    assert %{"points" => [%{"value" => 54, "source" => "apple_health"}]} =
             conn
             |> again(user)
             |> get("/api/me/daily-stats?metric=resting_hr&range=1m")
             |> json_response(200)

    # Today's steps keep growing: the later count replaces the earlier one.
    assert %{"counts" => %{"imported" => 1}} =
             conn
             |> ingest(user, %{
               "dailies" => [%{"date" => Date.to_iso8601(today), "steps" => 6400}]
             })
             |> json_response(200)

    assert %{"points" => [_, %{"value" => 6400}]} =
             conn
             |> again(user)
             |> get("/api/me/daily-stats?metric=steps&range=1m")
             |> json_response(200)

    assert %{"visible" => true, "provider" => "apple_health", "providers" => ["apple_health"]} =
             conn |> again(user) |> get("/api/me/devices/summary") |> json_response(200)

    assert %{
             "activities" => [%{"provider" => "apple_health"}],
             "daily_stats" => [_, _],
             "connections" => [%{"provider" => "apple_health", "status" => "active"}],
             "imports" => imports
           } = conn |> again(user) |> get("/api/me/devices/export") |> json_response(200)

    assert length(imports) == 6
  end

  test "health data waits for the consent and is picked up when sent again", %{
    conn: conn,
    user: user
  } do
    connect!(conn, user, "health_connect", %{
      sync_prefs: %{sleep: false, weight: false, resting_hr: false, steps: false}
    })

    # Turned on without the consent (another device of the same account could
    # have granted it and then it was withdrawn): the import is set aside.
    Palee.Repo.query!(
      "UPDATE device_connections SET sync_prefs = sync_prefs || '{\"steps\": true}' WHERE user_id = $1",
      [Ecto.UUID.dump!(user.id)]
    )

    day = %{"dailies" => [%{"date" => Date.to_iso8601(Date.utc_today()), "steps" => 100}]}

    assert %{"counts" => %{"ignored" => 1}} =
             conn |> ingest(user, day, "health_connect") |> json_response(200)

    conn
    |> again(user)
    |> patch("/api/me/devices/phone/health_connect", %{
      sync_prefs: %{steps: true},
      health_data_consent: true
    })
    |> json_response(200)

    assert %{"counts" => %{"imported" => 1}} =
             conn |> ingest(user, day, "health_connect") |> json_response(200)
  end

  test "a workout Garmin already sent is not doubled by the phone", %{conn: conn, user: user} do
    FakeGarminClient.configure()

    %{"authorize_url" => url} =
      conn
      |> again(user)
      |> post("/api/me/devices/garmin/connect", %{health_data_consent: true, backfill_days: 0})
      |> json_response(200)

    %{"state" => state} = url |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query()
    build_conn() |> get("/api/integrations/garmin/callback", %{state: state, code: "code-1"})

    start = ~U[2026-10-20 07:00:00Z]

    build_conn()
    |> put_req_header("content-type", "application/json")
    |> put_req_header("garmin-client-id", FakeGarminClient.client_id())
    |> post(
      "/api/integrations/garmin/push",
      Jason.encode!(%{
        "activities" => [
          %{
            "userId" => "garmin-user-1",
            "summaryId" => "g-1",
            "activityType" => "RUNNING",
            "startTimeInSeconds" => DateTime.to_unix(start),
            "durationInSeconds" => 1800
          }
        ]
      })
    )
    |> json_response(200)

    connect!(conn, user)

    # Garmin Connect wrote the same run into Apple Health a minute off.
    assert %{"counts" => %{"ignored" => 1}} =
             conn
             |> ingest(user, %{"activities" => [workout("hk-g-1", DateTime.add(start, 60), 30)]})
             |> json_response(200)

    %{"items" => items} =
      conn
      |> again(user)
      |> get("/api/me/journal", %{kinds: "device_activity"})
      |> json_response(200)

    assert [%{"entry" => %{"provider" => "garmin"}}] = items
  end

  test "invalid records are counted, oversized batches refused", %{conn: conn, user: user} do
    connect!(conn, user)

    assert %{"counts" => %{"ignored" => 1}} =
             conn
             |> ingest(user, %{
               "activities" => [
                 %{
                   "id" => "bad",
                   "start" => "2026-10-20T08:00:00Z",
                   "end" => "2026-10-20T07:00:00Z"
                 }
               ]
             })
             |> json_response(200)

    many = for i <- 1..501, do: %{"date" => "2026-10-20", "steps" => i}

    assert %{"code" => "phone_health_batch_too_large"} =
             conn |> ingest(user, %{"dailies" => many}) |> json_response(422)
  end

  test "disconnect keeps or deletes what the phone brought in", %{conn: conn, user: user} do
    connect!(conn, user)
    start = ~U[2026-10-19 17:00:00Z]

    conn
    |> ingest(user, %{
      "activities" => [workout("hk-1", start, 50)],
      "dailies" => [%{"date" => "2026-10-19", "steps" => 12_000}]
    })
    |> json_response(200)

    assert %{"status" => "revoked", "deleted" => nil} =
             conn
             |> again(user)
             |> delete("/api/me/devices/phone/apple_health")
             |> json_response(200)

    assert %{"status" => "native_only"} = row(conn, user, "apple_health")

    assert %{"code" => "phone_health_not_connected"} =
             conn |> ingest(user, %{"activities" => []}) |> json_response(422)

    connect!(conn, user)

    assert %{"deleted" => %{"activities" => 1, "daily_stats" => 1, "imports" => 2}} =
             conn
             |> again(user)
             |> delete("/api/me/devices/phone/apple_health?delete_data=true")
             |> json_response(200)

    assert %{"code" => "not_found"} =
             conn
             |> again(user)
             |> delete("/api/me/devices/phone/health_connect")
             |> json_response(404)
  end

  test "someone else's session sees and changes none of it", %{conn: conn, user: user} do
    connect!(conn, user)

    conn
    |> ingest(user, %{"activities" => [workout("hk-private", ~U[2026-10-18 06:00:00Z], 30)]})
    |> json_response(200)

    other = user_fixture(%{role: :member})

    assert %{"activities" => [], "connections" => []} =
             build_conn()
             |> put_bearer_token(other)
             |> get("/api/me/devices/export")
             |> json_response(200)
  end
end
