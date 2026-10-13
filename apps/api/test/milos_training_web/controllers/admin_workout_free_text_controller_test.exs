defmodule MilosTrainingWeb.AdminWorkoutFreeTextControllerTest do
  use MilosTrainingWeb.ConnCase, async: false

  alias MilosTraining.{Identity, Organizations}

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

  test "members cannot use the workout assistant", %{conn: conn} do
    {conn, organization} = authenticate(conn, "free_text_ai_member", :member)

    conn
    |> post("/api/org/#{organization.slug}/admin/workouts/free-text/analyze", %{text: "Run 5k"})
    |> json_response(403)
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
