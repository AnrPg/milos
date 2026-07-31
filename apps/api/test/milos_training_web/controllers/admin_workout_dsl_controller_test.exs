defmodule MilosTrainingWeb.AdminWorkoutDslControllerTest do
  use MilosTrainingWeb.ConnCase, async: false

  alias MilosTraining.Identity

  test "admin can parse and canonically format Quick Text", %{conn: conn} do
    conn = authenticate_as_admin(conn, "dsl_preview_admin")

    source = """
    [workout]
    dsl-version: 1
    title: Quick Strength
    type: strength
    [section: untimed]
    title: Main
    [exercise: Deadlift]
    sets: 3
    reps: 5
    load: 100 kg
    [/exercise]
    [/section]
    [/workout]
    """

    response =
      conn
      |> post("/api/admin/workouts/dsl/parse", %{source: source})
      |> json_response(200)

    assert response["workout"]["title"] == "Quick Strength"
    assert response["formatted_source"] =~ "load: 100 kg"
    assert "untimed" in response["vocabulary"]["section_formats"]
  end

  test "invalid Quick Text returns source-positioned diagnostics", %{conn: conn} do
    conn = authenticate_as_admin(conn, "dsl_diagnostic_admin")

    response =
      conn
      |> post("/api/admin/workouts/dsl/parse", %{source: "[workout]\n[/workout]"})
      |> json_response(422)

    assert Enum.any?(response["diagnostics"], fn diagnostic ->
             diagnostic["code"] == "missing_dsl_version" and diagnostic["line"] == 1
           end)
  end

  test "member cannot use admin DSL tooling", %{conn: conn} do
    {:ok, member} =
      Identity.register(%{
        nickname: "dsl_preview_member",
        password: "S3cur3P@ss!",
        role: :member
      })

    conn
    |> put_bearer_token(member)
    |> post("/api/admin/workouts/dsl/parse", %{source: ""})
    |> json_response(403)
  end

  defp authenticate_as_admin(conn, nickname) do
    {:ok, user} =
      Identity.register(%{
        nickname: nickname,
        password: "S3cur3P@ss!",
        role: :member
      })

    {:ok, admin} = Identity.update_role(user, :admin)
    put_bearer_token(conn, admin)
  end
end
