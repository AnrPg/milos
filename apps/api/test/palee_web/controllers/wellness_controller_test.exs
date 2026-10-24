defmodule PaleeWeb.WellnessControllerTest do
  use PaleeWeb.ConnCase, async: false

  import Palee.TestFixtures

  setup %{conn: conn} do
    user = user_fixture(%{role: :member})
    conn = put_bearer_token(conn, user)

    assert %{"code" => "health_data_consent_required"} =
             conn
             |> post("/api/me/wellness/entries", %{kind: "water", value: %{ml: 250}})
             |> json_response(403)

    conn
    |> recycle()
    |> put_bearer_token(user)
    |> put("/api/me/body/consents/health_data")
    |> json_response(200)

    %{user: user, conn: conn |> recycle() |> put_bearer_token(user)}
  end

  test "log water, a night, a meal and a craving, read the day, undo and settle", %{
    conn: conn,
    user: user
  } do
    today = Date.utc_today() |> Date.to_iso8601()

    %{"entry" => glass} =
      conn
      |> post("/api/me/wellness/entries", %{kind: "water", value: %{ml: 250}})
      |> json_response(201)

    assert %{"kind" => "water", "value" => %{"ml" => 250}, "journal_visibility" => "private"} =
             glass

    %{"entry" => %{"value" => %{"minutes" => 420, "quality" => 4}}} =
      conn
      |> recycle()
      |> put_bearer_token(user)
      |> post("/api/me/wellness/entries", %{kind: "sleep", value: %{minutes: 420, quality: 4}})
      |> json_response(201)

    %{"entry" => meal} =
      conn
      |> recycle()
      |> put_bearer_token(user)
      |> post("/api/me/wellness/entries", %{
        kind: "meal",
        value: %{slot: "lunch", plan_fit: "in_plan"}
      })
      |> json_response(201)

    %{"craving" => craving} =
      conn
      |> recycle()
      |> put_bearer_token(user)
      |> post("/api/me/wellness/cravings", %{intensity: 7, triggers: ["boredom"]})
      |> json_response(201)

    assert %{"outcome" => nil, "triggers" => ["boredom"], "follow_up_at" => follow_up} = craving
    assert follow_up

    overview =
      conn
      |> recycle()
      |> put_bearer_token(user)
      |> get("/api/me/wellness", %{from: today, to: today})
      |> json_response(200)

    assert %{
             "preferences" => %{"water_goal_ml" => 2000, "glass_ml" => 250},
             "days" => [
               %{
                 "water" => %{"ml" => 250, "status" => "partial"},
                 "sleep" => %{"minutes" => 420, "status" => "full"},
                 "meals" => %{"count" => 1},
                 "cravings" => %{"count" => 1}
               }
             ],
             "week" => %{"nights_on_goal" => 1}
           } = overview

    assert length(overview["entries"]) == 3

    conn
    |> recycle()
    |> put_bearer_token(user)
    |> delete("/api/me/wellness/entries/#{glass["id"]}")
    |> response(204)

    assert %{"entry" => %{"value" => %{"slot" => "lunch", "plan_fit" => "off_plan"}}} =
             conn
             |> recycle()
             |> put_bearer_token(user)
             |> patch("/api/me/wellness/entries/#{meal["id"]}", %{
               value: %{slot: "lunch", plan_fit: "off_plan"}
             })
             |> json_response(200)

    assert %{"craving" => %{"outcome" => "resisted", "follow_up_at" => nil}} =
             conn
             |> recycle()
             |> put_bearer_token(user)
             |> patch("/api/me/wellness/cravings/#{craving["id"]}", %{outcome: "resisted"})
             |> json_response(200)
  end

  test "invalid values explain which field is wrong", %{conn: conn} do
    assert %{"code" => "invalid_wellness_value", "errors" => %{"quality" => _}} =
             conn
             |> post("/api/me/wellness/entries", %{kind: "sleep", value: %{quality: 9}})
             |> json_response(422)

    assert %{"code" => "unknown_wellness_kind"} =
             conn
             |> recycle()
             |> post("/api/me/wellness/entries", %{kind: "steps", value: %{}})
             |> json_response(422)
  end

  test "one-tap mood then stress keeps both answers of the day", %{conn: conn, user: user} do
    today = Date.utc_today() |> Date.to_iso8601()

    for {key, value} <- [{"mood", 3}, {"stress", 2}] do
      conn
      |> recycle()
      |> put_bearer_token(user)
      |> post("/api/wellbeing/check-ins", %{
        answers: [%{question_key: key, value: value}],
        recorded_tz: "Etc/UTC"
      })
      |> json_response(201)
    end

    assert %{"days" => [%{"mood" => %{"mood" => 3, "stress" => 2}}]} =
             conn
             |> recycle()
             |> put_bearer_token(user)
             |> get("/api/me/wellness", %{from: today, to: today})
             |> json_response(200)
  end

  test "preferences and erase", %{conn: conn, user: user} do
    assert %{
             "preferences" => %{
               "water_goal_ml" => 2000,
               "hidden_items" => [],
               "hide_macros" => false
             }
           } = conn |> get("/api/me/wellness/preferences") |> json_response(200)

    # ADR-194: the plan's macros can be hidden, and stay hidden.
    assert %{"preferences" => %{"hide_macros" => true, "water_goal_ml" => 2000}} =
             conn
             |> recycle()
             |> put_bearer_token(user)
             |> put("/api/me/wellness/preferences", %{hide_macros: true})
             |> json_response(200)

    assert %{"preferences" => %{"water_goal_ml" => 2500, "hidden_items" => ["meals"]}} =
             conn
             |> recycle()
             |> put_bearer_token(user)
             |> put("/api/me/wellness/preferences", %{
               water_goal_ml: 2500,
               hidden_items: ["meals"]
             })
             |> json_response(200)

    assert %{"preferences" => %{"item_order" => ["mood", "water", "sleep", "meals", "plan"]}} =
             conn
             |> recycle()
             |> put_bearer_token(user)
             |> put("/api/me/wellness/preferences", %{item_order: ["mood", "water"]})
             |> json_response(200)

    conn
    |> recycle()
    |> put_bearer_token(user)
    |> post("/api/me/wellness/cravings", %{intensity: 4, note: "after dinner"})
    |> json_response(201)

    export =
      conn
      |> recycle()
      |> put_bearer_token(user)
      |> get("/api/me/wellness/export?sections=wellness,cravings")

    assert [~s(attachment; filename="palee-wellness.json")] =
             get_resp_header(export, "content-disposition")

    assert %{
             "sections" => %{
               "wellness" => %{"entries" => [], "preferences" => %{"water_goal_ml" => 2500}},
               "cravings" => %{"cravings" => [%{"note" => "after dinner"}]}
             },
             "photos" => %{}
           } = json_response(export, 200)

    assert %{"erased" => %{"cravings" => 1, "wellness" => 0}} =
             conn
             |> recycle()
             |> put_bearer_token(user)
             |> delete("/api/me/wellness?sections=wellness,cravings")
             |> json_response(200)
  end
end
