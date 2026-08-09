defmodule MilosTrainingWeb.AdminWorkoutDslControllerTest do
  use MilosTrainingWeb.ConnCase, async: false

  alias MilosTraining.{Identity, Organizations}

  test "admin can parse and canonically format Quick Text", %{conn: conn} do
    {conn, organization} = authenticate_as_admin(conn, "dsl_preview_admin")

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
      |> post(
        "/api/org/#{organization.slug}/admin/workouts/dsl/parse",
        %{source: source}
      )
      |> json_response(200)

    assert response["workout"]["title"] == "Quick Strength"
    assert response["formatted_source"] =~ "load: 100 kg"
    assert "untimed" in response["vocabulary"]["section_formats"]
  end

  test "invalid Quick Text returns source-positioned diagnostics", %{conn: conn} do
    {conn, organization} = authenticate_as_admin(conn, "dsl_diagnostic_admin")

    response =
      conn
      |> post(
        "/api/org/#{organization.slug}/admin/workouts/dsl/parse",
        %{source: "[workout]\n[/workout]"}
      )
      |> json_response(422)

    assert Enum.any?(response["diagnostics"], fn diagnostic ->
             diagnostic["code"] == "missing_dsl_version" and diagnostic["line"] == 1
           end)
  end

  test "member cannot use admin DSL tooling", %{conn: conn} do
    {:ok, member} =
      Identity.register(%{
        nickname: "dsl_preview_member",
        password: "S3cur3P@ss!42",
        role: :member,
        email: "u#{System.unique_integer([:positive])}@placeholder.invalid"
      })

    {:ok, organization} = Organizations.create_organization(%{name: "DSL Member Gym"})

    {:ok, _membership} =
      Organizations.add_membership(%{
        organization_id: organization.id,
        user_id: member.id,
        role: :member,
        status: :active,
        joined_at: DateTime.utc_now()
      })

    conn
    |> put_bearer_token(member)
    |> post(
      "/api/org/#{organization.slug}/admin/workouts/dsl/parse",
      %{source: ""}
    )
    |> json_response(403)
  end

  test "admin can load the generated manual and all format templates", %{conn: conn} do
    {conn, organization} = authenticate_as_admin(conn, "dsl_manual_admin")

    response =
      conn
      |> get("/api/org/#{organization.slug}/admin/workouts/dsl/manual")
      |> json_response(200)

    assert response["version"] == 1
    assert map_size(response["templates"]["sections"]) == 19
    assert length(response["vocabulary"]["exercise_catalog"]) > 100
    assert response["markdown"] =~ "Quick Text"
  end

  test "revisioned autosave rejects a stale editor and retained source can be reloaded", %{
    conn: conn
  } do
    {admin_conn, organization} = authenticate_as_admin(conn, "dsl_revision_admin")

    draft =
      admin_conn
      |> post("/api/org/#{organization.slug}/admin/workouts")
      |> json_response(201)
      |> Map.fetch!("draft")

    source = valid_source("Revision safety", "Deadlift")

    saved =
      admin_conn
      |> recycle()
      |> put_req_header("content-type", "application/json")
      |> patch(
        "/api/org/#{organization.slug}/admin/workouts/#{draft["id"]}/draft",
        %{
          authoring_mode: "quick_text",
          dsl_version: 1,
          dsl_source: source,
          dsl_document: %{type: "doc"},
          expected_source_revision: 0,
          draft_data: %{authoring_mode: "quick_text", dsl_source: source}
        }
      )
      |> json_response(200)
      |> Map.fetch!("draft")

    assert saved["dsl_source_revision"] == 1

    stale =
      admin_conn
      |> recycle()
      |> put_req_header("content-type", "application/json")
      |> patch(
        "/api/org/#{organization.slug}/admin/workouts/#{draft["id"]}/draft",
        %{
          dsl_source: String.replace(source, "Revision safety", "Stale overwrite"),
          expected_source_revision: 0
        }
      )
      |> json_response(409)

    assert stale["code"] == "stale_dsl_revision"

    retained =
      admin_conn
      |> recycle()
      |> get("/api/org/#{organization.slug}/admin/workouts/#{draft["id"]}/dsl")
      |> json_response(200)

    assert retained["source"] == source
    assert retained["source_revision"] == 1
    assert retained["authoring_mode"] == "quick_text"
  end

  test "direct publish retains free-text exercise source without warning acknowledgement", %{
    conn: conn
  } do
    {admin_conn, organization} = authenticate_as_admin(conn, "dsl_publish_admin")

    draft =
      admin_conn
      |> post("/api/org/#{organization.slug}/admin/workouts")
      |> json_response(201)
      |> Map.fetch!("draft")

    source = valid_source("Alias warning", "Conventional Deadlift")

    saved =
      admin_conn
      |> recycle()
      |> put_req_header("content-type", "application/json")
      |> patch(
        "/api/org/#{organization.slug}/admin/workouts/#{draft["id"]}/draft",
        %{
          authoring_mode: "quick_text",
          dsl_version: 1,
          dsl_source: source,
          expected_source_revision: 0,
          draft_data: %{authoring_mode: "quick_text", dsl_source: source}
        }
      )
      |> json_response(200)
      |> Map.fetch!("draft")

    published =
      admin_conn
      |> recycle()
      |> put_req_header("content-type", "application/json")
      |> post(
        "/api/org/#{organization.slug}/admin/workouts/#{draft["id"]}/dsl/publish",
        %{
          source: source,
          document: %{type: "doc"},
          expected_source_revision: saved["dsl_source_revision"],
          acknowledge_warnings: false
        }
      )
      |> json_response(200)

    assert published["workout"]["status"] == "published"
    assert published["workout"]["dsl_source"] == source
    assert published["diagnostics"] == []
    assert published["execution_preview"]["segment_count"] == 1

    assert get_in(published, [
             "workout",
             "sections",
             Access.at(0),
             "exercises",
             Access.at(0),
             "name"
           ]) ==
             "Conventional Deadlift"
  end

  defp authenticate_as_admin(conn, nickname) do
    {:ok, user} =
      Identity.register(%{
        nickname: nickname,
        password: "S3cur3P@ss!42",
        role: :member,
        email: "u#{System.unique_integer([:positive])}@placeholder.invalid"
      })

    {:ok, admin} = Identity.update_role(user, :admin)
    {:ok, organization} = Organizations.create_organization(%{name: "#{nickname} Gym"})

    {:ok, _membership} =
      Organizations.add_membership(%{
        organization_id: organization.id,
        user_id: admin.id,
        role: :owner,
        status: :active,
        joined_at: DateTime.utc_now()
      })

    {put_bearer_token(conn, admin), organization}
  end

  defp valid_source(title, exercise_name) do
    """
    [workout]
    dsl-version: 1
    title: #{title}
    type: strength
    [section: untimed]
    title: Main
    [exercise: #{exercise_name}]
    sets: 3
    reps: 5
    [/exercise]
    [/section]
    [/workout]
    """
  end
end
