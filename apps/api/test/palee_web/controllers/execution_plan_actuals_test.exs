defmodule PaleeWeb.ExecutionPlanActualsTest do
  @moduledoc "ADR-270: plan actuals sent with a structured_plan completion are stored and read back."
  use PaleeWeb.ConnCase, async: false

  import Palee.StructuredPlanFixtures

  alias Palee.{Execution, Identity, Organizations, Repo}
  alias Palee.Execution.ExecutionPlanSet

  defp create_user!(nickname, role) do
    {:ok, user} =
      Identity.register(%{
        nickname: nickname,
        password: "S3cur3P@ss!42",
        role: :member,
        email: "u#{System.unique_integer([:positive])}@placeholder.invalid"
      })

    user =
      if role == :admin do
        {:ok, admin} = Identity.update_role(user, :admin)
        admin
      else
        user
      end

    membership_role = if role == :admin, do: :owner, else: :member
    {:ok, _membership} = Organizations.ensure_legacy_membership_for_migration(user, membership_role)
    user
  end

  defp json(conn, method, path, body) do
    conn
    |> recycle()
    |> put_req_header("content-type", "application/json")
    |> dispatch(@endpoint, method, path, Jason.encode!(body))
  end

  defp plan_workout!(conn, admin) do
    admin_conn = put_bearer_token(conn, admin)
    base = "/api/org/#{Organizations.legacy_organization_slug()}/admin/workouts"
    draft_id = admin_conn |> post(base) |> json_response(201) |> get_in(["draft", "id"])

    admin_conn
    |> json(:post, "#{base}/#{draft_id}/publish", %{
      expected_source_revision: 0,
      title: "Plan Saturday",
      type: "crossfit",
      authoring_mode: "structured_plan",
      sections: [
        %{name: "Strength", order: 1, exercises: [], plan: Enum.at(program(), 0)},
        %{name: "Engine", order: 2, exercises: [], plan: Enum.at(program(), 7)}
      ]
    })
    |> json_response(200)
    |> Map.fetch!("workout")
  end

  defp actual(section_id, row_id, overrides) do
    Map.merge(
      %{
        section_id: section_id,
        row_id: row_id,
        exercise_name: "Back Squat",
        exercise_ref: nil,
        block_index: 0,
        round_index: 1,
        part_index: 0,
        phase_index: 0,
        interrupt: false,
        prescribed_reps_text: "12",
        prescribed_load_text: "60%",
        prescribed_reps: 12,
        prescribed_load_kg: 60,
        prescribed_load_pct: 60,
        one_rep_max_kg: 100,
        actual_reps: 12,
        actual_load_kg: 62.5,
        logged: true
      },
      overrides
    )
  end

  defp start!(athlete_conn, workout) do
    athlete_conn
    |> json(:post, "/api/executions", %{master_workout_id: workout["id"], source: "self_selected"})
    |> json_response(201)
    |> get_in(["execution", "id"])
  end

  test "completion stores plan actuals, reads them back and refuses ones the plan cannot produce",
       %{conn: conn} do
    admin = create_user!("plan_actuals_admin", :admin)
    athlete = create_user!("plan_actuals_member", :member)
    athlete_conn = put_bearer_token(conn, athlete)
    workout = plan_workout!(conn, admin)
    [strength, engine] = Enum.sort_by(workout["sections"], & &1["order"])
    execution_id = start!(athlete_conn, workout)
    path = "/api/executions/#{execution_id}/complete"

    # A row of another section is refused, and nothing is completed.
    athlete_conn
    |> json(:patch, path, %{plan_actuals: [actual(strength["id"], "r18", %{})]})
    |> json_response(400)

    actuals = [
      actual(strength["id"], "r1", %{}),
      actual(strength["id"], "r1", %{round_index: 2, actual_load_kg: 65, logged: false}),
      actual(engine["id"], "r18", %{
        exercise_name: "Burpee",
        block_index: -1,
        interrupt: true,
        round_index: 2,
        prescribed_load_text: "",
        prescribed_load_kg: nil,
        prescribed_load_pct: nil,
        one_rep_max_kg: nil,
        actual_reps: 10,
        actual_load_kg: nil
      })
    ]

    # What the web plan runner sends: its scores and elapsed time per plan
    # section, keyed by section id, next to the actuals.
    completed =
      athlete_conn
      |> json(:patch, path, %{
        timezone: "Europe/Athens",
        checked_exercise_ids: [],
        section_scores: [
          %{
            section_id: engine["id"],
            section_name: "Engine",
            value: 754,
            score_type: "time",
            source: "user",
            kind: "final"
          }
        ],
        total_elapsed_ms: 1_500_000,
        section_elapsed_ms: %{strength["id"] => 900_000, engine["id"] => 600_000},
        segment_cycle_counts: %{},
        plan_actuals: actuals
      })
      |> json_response(200)
      |> Map.fetch!("execution")

    assert [%{"section_id" => engine_id, "value" => 754, "score_type" => "time"}] =
             completed["section_scores"]

    assert engine_id == engine["id"]

    assert [first, second, burpee] = completed["plan_sets"]

    assert %{
             "section_id" => section_id,
             "row_id" => "r1",
             "round_index" => 1,
             "actual_load_kg" => 62.5,
             "prescribed_load_pct" => 60,
             "one_rep_max_kg" => 100,
             "logged" => true
           } = first

    assert section_id == strength["id"]
    assert %{"round_index" => 2, "actual_load_kg" => 65, "logged" => false} = second

    assert %{"interrupt" => true, "block_index" => -1, "round_index" => 2, "one_rep_max_kg" => nil} =
             burpee

    read =
      athlete_conn
      |> recycle()
      |> get("/api/executions/#{execution_id}")
      |> json_response(200)
      |> get_in(["execution", "plan_sets"])

    assert read == completed["plan_sets"]

    # The tenant's staff read them with the execution (RLS through the parent).
    assert conn
           |> put_bearer_token(admin)
           |> get("/api/executions/#{execution_id}")
           |> json_response(200)
           |> get_in(["execution", "plan_sets"]) == read

    # Owner rows under RLS: stored with the execution's owner and tenant.
    rows = Repo.all(ExecutionPlanSet)
    assert length(rows) == 3
    assert Enum.all?(rows, &(&1.user_id == athlete.id and &1.execution_id == execution_id))

    assert [_, _, _] = Execution.list_plan_sets([execution_id])
  end

  test "a completion without plan actuals stores none", %{conn: conn} do
    admin = create_user!("plan_actuals_other_admin", :admin)
    athlete_conn = put_bearer_token(conn, create_user!("plan_actuals_other_member", :member))
    workout = plan_workout!(conn, admin)
    execution_id = start!(athlete_conn, workout)

    assert athlete_conn
           |> json(:patch, "/api/executions/#{execution_id}/complete", %{})
           |> json_response(200)
           |> get_in(["execution", "plan_sets"]) == []
  end
end
