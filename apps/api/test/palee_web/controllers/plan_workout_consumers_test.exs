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
  alias Palee.Application.{AthleteTrainingVolume, CreatePR, ListWorkoutExecutions}
  alias Palee.Identity.UserContext
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

    {:ok, _pr} =
      CreatePR.call(UserContext.new(athlete), %{
        "name" => "Back squat 1RM",
        "current_score" => 100,
        "unit" => "kg",
        "beaten_on" => Date.to_iso8601(Date.utc_today())
      })

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
          %{section_id: amrap["id"], value: "3+20", score_type: "rounds_reps"},
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
          squat(strength["id"], 3, 8, 70, false),
          # 75% of a 1RM the runner did not know: the server reads it from the PRs.
          %{squat(strength["id"], 4, 8, nil, false) | prescribed_load_pct: 75}
        ]
      })
      |> json_response(200)
      |> Map.fetch!("execution")

    assert %{"status" => "completed"} = completed

    assert completed["section_scores"]
           |> Enum.filter(&(&1["source"] != "auto"))
           |> Map.new(&{&1["section_id"], &1["value"]}) ==
             %{amrap["id"] => "3+20", thrusters["id"] => "6:10"}

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
             %{"source" => "actuals", "totals" => %{"sets" => 4, "logged_sets" => 2}},
             # 3 full rounds (45 pull-ups, 5 + 10 + 15 snatches @ 40/45/50 kg)
             # and 20 reps of the 4th: 15 pull-ups, 5 snatches @ 55 kg.
             %{"source" => "prescription", "totals" => %{"reps" => 95, "volume_kg" => 1675}},
             # 75 thrusters and 3 interruptions of 10 burpees in 6:10.
             %{"source" => "prescription", "totals" => %{"reps" => 105}}
           ] = workload["sections"]

    # 12×60 + 10×65 + 8×70 + 8×75 (75% of the 100 kg 1RM) = 2530 kg of squats.
    assert %{"volume_kg" => 4205, "estimated" => false} = workload["totals"]

    # Training volume (coverage, qualities, load): sets done per exercise.
    %{performances: [performance]} =
      AthleteTrainingVolume.load(%{user_id: athlete.id, organization_id: nil}, nil)

    assert performance.volume_kg == 4205

    assert performance.exercises |> Map.new(&{&1.name, &1.sets}) == %{
             "Back Squat" => 4,
             "Butterfly Pull-up" => 4,
             "Power Snatch" => 3,
             "Thruster" => 1,
             "Burpee over Bar" => 3
           }

    # Execution lists (journal, Πρόοδος stats): the plan workload and the heaviest sets.
    {:ok, [listed]} =
      ListWorkoutExecutions.call(%{user_id: athlete.id, organization_id: nil}, athlete.id)

    assert %{volume_kg: 4205, sets: 15.33, logged_sets: 2, top_sets: top_sets} =
             listed.plan_workload

    assert %{load_kg: 75, reps: 8} = Enum.find(top_sets, &(&1.name == "Back Squat"))

    assert %{totals: %{volume_kg: 4205}} = ProgressStats.build([listed], Date.utc_today())
  end

  test "a Quick Text or legacy editor publish never drops a structured plan", %{conn: conn} do
    admin = create_user!("plan_guard_admin", :admin)
    admin_conn = put_bearer_token(conn, admin)
    workout = plan_workout!(conn, admin)
    base = org_path("/admin/workouts")

    assert %{"code" => "structured_plan_mode_change"} =
             admin_conn
             |> json(:post, "#{base}/#{workout["id"]}/dsl/publish", %{
               source: "Back squat 5x5 @ 100kg",
               expected_source_revision: 0,
               acknowledge_warnings: true
             })
             |> json_response(409)

    assert %{"code" => "structured_plan_mode_change"} =
             admin_conn
             |> json(:post, "#{base}/#{workout["id"]}/publish", %{
               title: "Legacy save",
               type: "crossfit",
               authoring_mode: "structured",
               sections: [
                 %{name: "Main", order: 1, exercises: [%{name: "Back squat", order: 1, sets: 5}]}
               ]
             })
             |> json_response(409)

    # The plan is untouched.
    sections =
      admin_conn
      |> recycle()
      |> get("#{base}/#{workout["id"]}")
      |> json_response(200)
      |> get_in(["workout", "sections"])

    assert Enum.all?(sections, &is_map(&1["plan"]))
  end

  test "a legacy editor's draft save never replaces a structured plan", %{conn: conn} do
    admin = create_user!("plan_draft_guard_admin", :admin)
    admin_conn = put_bearer_token(conn, admin)
    workout = plan_workout!(conn, admin)
    base = org_path("/admin/workouts")
    legacy_sections = [%{name: "Main", order: 1, exercises: [%{name: "Back squat", order: 1}]}]

    for draft <- [
          %{authoring_mode: "structured", title: "Legacy", sections: legacy_sections},
          %{authoring_mode: "quick_text", title: "Quick Text"},
          %{title: "No mode", sections: legacy_sections}
        ] do
      assert %{"code" => "structured_plan_mode_change"} =
               admin_conn
               |> json(:patch, "#{base}/#{workout["id"]}/draft", %{
                 expected_source_revision: workout["dsl_source_revision"],
                 draft_data: draft
               })
               |> json_response(409)
    end

    # The publish that follows still sees a plan workout: refused, plans intact.
    assert %{"code" => "structured_plan_mode_change"} =
             admin_conn
             |> json(:post, "#{base}/#{workout["id"]}/publish", %{
               expected_source_revision: workout["dsl_source_revision"],
               title: "Legacy save",
               type: "crossfit",
               sections: legacy_sections
             })
             |> json_response(409)

    stored =
      admin_conn
      |> recycle()
      |> get("#{base}/#{workout["id"]}")
      |> json_response(200)
      |> Map.fetch!("workout")

    assert stored["authoring_mode"] == "structured_plan"
    assert length(stored["sections"]) == 3
    assert Enum.all?(stored["sections"], &is_map(&1["plan"]))

    # The structured WOD editor's own draft save goes through.
    assert %{"draft" => %{"id" => _}} =
             admin_conn
             |> json(:patch, "#{base}/#{workout["id"]}/draft", %{
               expected_source_revision: workout["dsl_source_revision"],
               draft_data: %{
                 authoring_mode: "structured_plan",
                 title: "Plan consumers",
                 sections: [%{name: "Strength", order: 1, plan: Enum.at(program(), 0)}]
               }
             })
             |> json_response(200)
  end
end
