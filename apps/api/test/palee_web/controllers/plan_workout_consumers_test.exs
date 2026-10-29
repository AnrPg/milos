defmodule PaleeWeb.PlanWorkoutConsumersTest do
  @moduledoc """
  ADR-270: a structured plan workout is consumed end to end like any other:
  it runs on its plan's clock, the plan runner's completion (scores, section
  times, actuals) is accepted, and history, training volume and the
  completion facts count what was done in each set.
  """
  use PaleeWeb.ConnCase, async: false

  import Palee.StructuredPlanFixtures

  alias Palee.Analytics.Domain.ProgressStats
  alias Palee.Application.{AthleteTrainingVolume, ListWorkoutExecutions}
  alias Palee.{Identity, Organizations}

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

    {:ok, _membership} =
      Organizations.ensure_legacy_membership_for_migration(user, membership_role)

    user
  end

  defp json(conn, method, path, body) do
    conn
    |> recycle()
    |> put_req_header("content-type", "application/json")
    |> dispatch(@endpoint, method, path, Jason.encode!(body))
  end

  defp org_path(path), do: "/api/org/#{Organizations.legacy_organization_slug()}#{path}"

  # Strength 4 sets (Back Squat 12-10-8-8 @ 60% +5), an AMRAP of 7' and a
  # For Time with an interruption every 2:00.
  defp plan_workout!(conn, admin) do
    admin_conn = put_bearer_token(conn, admin)
    base = org_path("/admin/workouts")
    draft_id = admin_conn |> post(base) |> json_response(201) |> get_in(["draft", "id"])

    admin_conn
    |> json(:post, "#{base}/#{draft_id}/publish", %{
      expected_source_revision: 0,
      title: "Plan consumers",
      type: "crossfit",
      authoring_mode: "structured_plan",
      sections: [
        %{name: "Strength", order: 1, exercises: [], plan: Enum.at(program(), 0)},
        %{name: "AMRAP", order: 2, exercises: [], plan: Enum.at(program(), 6)},
        %{name: "Thrusters", order: 3, exercises: [], plan: Enum.at(program(), 7)}
      ]
    })
    |> json_response(200)
    |> Map.fetch!("workout")
  end

  defp squat(section_id, round, reps, kg, logged) do
    %{
      section_id: section_id,
      row_id: "r1",
      exercise_name: "Back Squat",
      exercise_ref: nil,
      block_index: 0,
      round_index: round,
      part_index: 0,
      phase_index: 0,
      interrupt: false,
      prescribed_reps_text: "",
      prescribed_load_text: "",
      prescribed_reps: reps,
      prescribed_load_kg: kg,
      prescribed_load_pct: nil,
      one_rep_max_kg: nil,
      actual_reps: reps,
      actual_load_kg: kg,
      logged: logged
    }
  end

  test "a plan workout runs, completes and is counted set by set", %{conn: conn} do
    admin = create_user!("plan_consumers_admin", :admin)
    athlete = create_user!("plan_consumers_member", :member)
    athlete_conn = put_bearer_token(conn, athlete)
    workout = plan_workout!(conn, admin)
    [strength, amrap, thrusters] = Enum.sort_by(workout["sections"], & &1["order"])

    segments =
      athlete_conn
      |> recycle()
      |> get("/api/workouts/#{workout["id"]}/timer-sequence?source=self_selected")
      |> json_response(200)
      |> Map.fetch!("segments")

    # One segment per plan section, from its clock (`PlanTimer`), scored as the plan says.
    by_section = Map.new(segments, &{&1["section_id"], &1})
    assert %{"scoreable" => false} = by_section[strength["id"]]

    assert %{"kind" => "countdown", "duration_seconds" => 420, "scoreable" => true} =
             by_section[amrap["id"]]

    assert %{"kind" => "countup", "score_config" => %{"type" => "time"}} =
             by_section[thrusters["id"]]

    execution_id =
      athlete_conn
      |> json(:post, "/api/executions", %{
        master_workout_id: workout["id"],
        source: "self_selected"
      })
      |> json_response(201)
      |> get_in(["execution", "id"])

    # What the plan runner sends.
    completed =
      athlete_conn
      |> json(:patch, "/api/executions/#{execution_id}/complete", %{
        checked_exercise_ids: [],
        section_scores: [
          %{section_id: amrap["id"], value: "3+4", score_type: "rounds_reps"},
          %{section_id: thrusters["id"], value: "6:10", score_type: "time"}
        ],
        total_elapsed_ms: 1_500_000,
        section_elapsed_ms: %{
          strength["id"] => 710_000,
          amrap["id"] => 420_000,
          thrusters["id"] => 370_000
        },
        segment_cycle_counts: %{},
        plan_actuals: [
          squat(strength["id"], 1, 12, 60, true),
          squat(strength["id"], 2, 10, 65, true),
          squat(strength["id"], 3, 8, 70, false)
        ]
      })
      |> json_response(200)
      |> Map.fetch!("execution")

    assert %{"status" => "completed"} = completed

    assert completed["section_scores"]
           |> Enum.filter(&(&1["source"] != "auto"))
           |> Map.new(&{&1["section_id"], &1["value"]}) ==
             %{amrap["id"] => "3+4", thrusters["id"] => "6:10"}

    # History: the plan's flows and what was done.
    page =
      athlete_conn
      |> recycle()
      |> get(org_path("/me/history"))
      |> json_response(200)

    assert [entry] = page["entries"]
    assert Enum.map(entry["workout"]["sections"], & &1["flow"]) == ["sets", "amrap", "for_time"]
    assert Enum.map(entry["workout"]["sections"], & &1["format"]) == ["sets", "amrap", "for_time"]

    workload = entry["performance"]["workload"]

    assert [
             %{"source" => "actuals", "totals" => %{"sets" => 3, "logged_sets" => 2}},
             # 3 full rounds: 45 pull-ups, 5 + 10 + 15 snatches @ 40/45/50 kg.
             %{"source" => "prescription", "totals" => %{"reps" => 75, "volume_kg" => 1400}},
             # 75 thrusters and 3 interruptions of 10 burpees in 6:10.
             %{"source" => "prescription", "totals" => %{"reps" => 105}}
           ] = workload["sections"]

    # 12×60 + 10×65 + 8×70 = 1930 kg of squats.
    assert %{"volume_kg" => 3330, "estimated" => false} = workload["totals"]

    # Training volume (coverage, qualities, load): sets done per exercise.
    %{performances: [performance]} =
      AthleteTrainingVolume.load(%{user_id: athlete.id, organization_id: nil}, nil)

    assert performance.volume_kg == 3330

    assert performance.exercises |> Map.new(&{&1.name, &1.sets}) == %{
             "Back Squat" => 3,
             "Butterfly Pull-up" => 3,
             "Power Snatch" => 3,
             "Thruster" => 1,
             "Burpee over Bar" => 3
           }

    # Execution lists (journal, Πρόοδος stats): the plan workload and the heaviest sets.
    {:ok, [listed]} =
      ListWorkoutExecutions.call(%{user_id: athlete.id, organization_id: nil}, athlete.id)

    assert %{volume_kg: 3330, sets: 13, logged_sets: 2, top_sets: top_sets} = listed.plan_workload

    assert %{load_kg: 70, reps: 8} = Enum.find(top_sets, &(&1.name == "Back Squat"))

    assert %{totals: %{volume_kg: 3330}} = ProgressStats.build([listed], Date.utc_today())
  end
end
