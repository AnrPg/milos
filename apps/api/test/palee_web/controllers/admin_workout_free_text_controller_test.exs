defmodule PaleeWeb.AdminWorkoutFreeTextControllerTest do
  use PaleeWeb.ConnCase, async: false

  alias Palee.{Identity, Organizations}

  test "admin receives canonical fields, actionable issues and suggestions", %{conn: conn} do
    {conn, organization} = authenticate(conn, "free_text_ai_admin", :owner)

    response =
      conn
      |> post("/api/org/#{organization.slug}/admin/workouts/free-text/analyze", %{
        text: "Back sqaut 5x5 @ 100kg",
        locale: "el"
      })
      |> json_response(200)

    assert response["workout"]["title"] == "Back squat day"
    assert [%{"exercises" => [exercise]}] = response["workout"]["sections"]
    assert exercise["load_value"] == 100

    assert [issue] = response["issues"]
    assert issue["message"] == "locale=el"
    assert issue["required"] == true

    assert issue["suggestion"]["text_edit"] == %{
             "find" => "Back sqaut",
             "replace" => "Back squat"
           }

    assert Enum.any?(
             response["suggestions"],
             &(&1["path"] == "sections.0.exercises.0.rest_seconds" and &1["value"] == 120)
           )

    assert response["summary"]["blocking"] == 0
  end

  test "blank text is rejected with an actionable code", %{conn: conn} do
    {conn, organization} = authenticate(conn, "free_text_ai_blank", :owner)

    response =
      conn
      |> post("/api/org/#{organization.slug}/admin/workouts/free-text/analyze", %{text: "   "})
      |> json_response(422)

    assert response["code"] == "text_required"
  end

  test "assistant outages map to explicit status codes", %{conn: conn} do
    {conn, organization} = authenticate(conn, "free_text_ai_outage", :owner)

    Process.put(:fake_workout_text_analyzer, fn _text, _options ->
      {:error, :analyzer_not_configured}
    end)

    response =
      conn
      |> post("/api/org/#{organization.slug}/admin/workouts/free-text/analyze", %{text: "Run 5k"})
      |> json_response(503)

    assert response["code"] == "analyzer_not_configured"
  end

  # The edge gateway replaces upstream 502s with its own HTML page, which hides
  # the JSON code from the browser. Provider failures answer 424 instead.
  for reason <- [:analyzer_quota_exhausted, :analyzer_unavailable, :analyzer_invalid_response] do
    test "#{reason} answers 424 with an explicit code", %{conn: conn} do
      {conn, organization} =
        authenticate(conn, "ft_ai_#{System.unique_integer([:positive])}", :owner)

      Process.put(:fake_workout_text_analyzer, fn _text, _options ->
        {:error, unquote(reason)}
      end)

      response =
        conn
        |> post("/api/org/#{organization.slug}/admin/workouts/free-text/analyze", %{
          text: "Run 5k"
        })
        |> json_response(424)

      assert response["code"] == Atom.to_string(unquote(reason))
    end
  end

  test "members cannot use the workout assistant", %{conn: conn} do
    {conn, organization} = authenticate(conn, "free_text_ai_member", :member)

    conn
    |> post("/api/org/#{organization.slug}/admin/workouts/free-text/analyze", %{text: "Run 5k"})
    |> json_response(403)
  end

  describe "ADR-180: the gym's WOD assistant switch" do
    test "is on by default, and off it stops the assistant before any call", %{conn: conn} do
      {conn, organization} = authenticate(conn, "free_text_ai_switch", :owner)
      base = "/api/org/#{organization.slug}/admin"

      assert %{"wod_assistant_enabled" => true} =
               conn |> get("#{base}/workouts/authoring-settings") |> json_response(200)

      assert %{"workouts" => %{"wod_assistant_enabled" => false}} =
               conn
               |> recycle()
               |> put_req_header("content-type", "application/json")
               |> patch(
                 "#{base}/settings",
                 Jason.encode!(%{workouts: %{wod_assistant_enabled: false}})
               )
               |> json_response(200)

      assert %{"wod_assistant_enabled" => false} =
               conn
               |> recycle()
               |> get("#{base}/workouts/authoring-settings")
               |> json_response(200)

      Process.put(:fake_workout_text_analyzer, fn _text, _options ->
        flunk("the assistant must not be called when the gym switched it off")
      end)

      assert %{"code" => "assistant_disabled"} =
               conn
               |> recycle()
               |> put_req_header("content-type", "application/json")
               |> post("#{base}/workouts/free-text/analyze", Jason.encode!(%{text: "Run 5k"}))
               |> json_response(403)
    end

    test "a member cannot read the authoring settings", %{conn: conn} do
      {conn, organization} = authenticate(conn, "free_text_ai_switch_member", :member)

      conn
      |> get("/api/org/#{organization.slug}/admin/workouts/authoring-settings")
      |> json_response(403)
    end
  end

  defp authenticate(conn, nickname, membership_role) do
    {:ok, user} =
      Identity.register(%{
        nickname: nickname,
        password: "S3cur3P@ss!42",
        role: :member,
        email: "u#{System.unique_integer([:positive])}@placeholder.invalid"
      })

    {:ok, user} =
      if membership_role == :member, do: {:ok, user}, else: Identity.update_role(user, :admin)

    {:ok, organization} = Organizations.create_organization(%{name: "#{nickname} Gym"})

    {:ok, _membership} =
      Organizations.add_membership(%{
        organization_id: organization.id,
        user_id: user.id,
        role: membership_role,
        status: :active,
        joined_at: DateTime.utc_now()
      })

    {put_bearer_token(conn, user), organization}
  end
end
