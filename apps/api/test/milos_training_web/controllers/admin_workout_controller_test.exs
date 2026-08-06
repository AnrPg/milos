defmodule MilosTrainingWeb.AdminWorkoutControllerTest do
  use MilosTrainingWeb.ConnCase, async: false

  alias MilosTraining.{Identity, Organizations}

  describe "admin workout draft flow" do
    test "admin can create, autosave, inspect, and publish a draft", %{conn: conn} do
      admin_conn = authenticate_as_admin(conn, "admin_draft_author")

      {:ok, _levels} =
        MilosTraining.Workouts.replace_scale_levels([
          %{slug: "scaled", label: "Scaled", sort_order: 1},
          %{slug: "rx", label: "Rx", sort_order: 2},
          %{slug: "competition", label: "Competition", sort_order: 3}
        ])

      create_conn = post(admin_conn, "/api/org/#{MilosTraining.Organizations.legacy_organization_slug()}/admin/workouts")
      draft = json_response(create_conn, 201)["draft"]
      draft_id = draft["id"]

      assert draft["status"] == "draft"

      draft_payload = %{
        title: "Engine Ladder",
        type: "crossfit",
        sections: [
          %{
            name: "Main Set",
            order: 9,
            scoreable: true,
            score_config: %{type: "time", unit: "min", label: "Finish time"},
            timer_config: %{type: "for_time", time_cap_seconds: 900},
            exercises: [
              %{
                name: "Wall Balls",
                sets: 1,
                prescription_value: 20,
                prescription_unit: "reps",
                order: 99,
                variations: [
                  %{scale_level_slug: "scaled", prescription_value: 16},
                  %{scale_level_slug: "competition", prescription_value: 24}
                ]
              },
              %{
                name: "Burpees",
                sets: 1,
                prescription_value: 15,
                prescription_unit: "reps",
                order: 42,
                variations: [
                  %{scale_level_slug: "competition", prescription_value: 18}
                ]
              }
            ]
          }
        ]
      }

      autosave_conn =
        admin_conn
        |> recycle()
        |> put_req_header("content-type", "application/json")
        |> patch("/api/org/#{MilosTraining.Organizations.legacy_organization_slug()}/admin/workouts/#{draft_id}/draft", Jason.encode!(draft_payload))

      assert json_response(autosave_conn, 200)["draft"]["status"] == "draft"

      show_conn = get(admin_conn |> recycle(), "/api/org/#{MilosTraining.Organizations.legacy_organization_slug()}/admin/workouts/#{draft_id}")
      shown_workout = json_response(show_conn, 200)["workout"]

      assert shown_workout["status"] == "draft"
      assert shown_workout["draft_data"]["title"] == "Engine Ladder"

      publish_conn =
        admin_conn
        |> recycle()
        |> put_req_header("content-type", "application/json")
        |> post("/api/org/#{MilosTraining.Organizations.legacy_organization_slug()}/admin/workouts/#{draft_id}/publish", Jason.encode!(%{}))

      workout = json_response(publish_conn, 200)["workout"]

      assert workout["status"] == "published"
      assert workout["title"] == "Engine Ladder"

      [section] = workout["sections"]
      assert section["name"] == "Main Set"

      [first_exercise, second_exercise] = section["exercises"]
      assert {first_exercise["name"], first_exercise["order"]} == {"Wall Balls", 1}
      assert {second_exercise["name"], second_exercise["order"]} == {"Burpees", 2}

      assert Enum.map(workout["available_scale_levels"], & &1["slug"]) == [
               "scaled",
               "competition"
             ]
    end

    test "publishes a container whose exercises are in nested child sections", %{conn: conn} do
      admin_conn = authenticate_as_admin(conn, "nested_draft_author")
      create_conn = post(admin_conn, "/api/org/#{MilosTraining.Organizations.legacy_organization_slug()}/admin/workouts")
      draft_id = json_response(create_conn, 201)["draft"]["id"]

      draft_payload = %{
        title: "Nested Strength",
        type: "strength",
        sections: [
          %{
            name: "Main Course",
            order: 1,
            exercises: [],
            sections: [
              %{
                name: "Part A",
                order: 1,
                exercises: [
                  %{
                    name: "Back Squat",
                    order: 1,
                    sets: 5,
                    prescription_value: 5,
                    prescription_unit: "reps"
                  }
                ]
              }
            ]
          }
        ]
      }

      autosave_conn =
        admin_conn
        |> recycle()
        |> put_req_header("content-type", "application/json")
        |> patch("/api/org/#{MilosTraining.Organizations.legacy_organization_slug()}/admin/workouts/#{draft_id}/draft", Jason.encode!(draft_payload))

      assert json_response(autosave_conn, 200)["draft"]["id"] == draft_id

      publish_conn =
        admin_conn
        |> recycle()
        |> put_req_header("content-type", "application/json")
        |> post("/api/org/#{MilosTraining.Organizations.legacy_organization_slug()}/admin/workouts/#{draft_id}/publish", Jason.encode!(%{}))

      assert json_response(publish_conn, 200)["workout"]["status"] == "published"
    end

    test "publishes a free-text workout without structured sections", %{conn: conn} do
      admin_conn = authenticate_as_admin(conn, "free_text_author")

      draft_id =
        post(admin_conn, "/api/org/#{MilosTraining.Organizations.legacy_organization_slug()}/admin/workouts") |> json_response(201) |> get_in(["draft", "id"])

      draft_payload = %{
        title: "Friday Board WOD",
        type: "crossfit",
        authoring_mode: "free_text",
        free_text_body: "AMRAP 20\n10 pull-ups\n15 wall balls",
        free_text_document: %{
          type: "doc",
          content: [%{type: "paragraph", content: [%{type: "text", text: "AMRAP 20"}]}]
        },
        sections: []
      }

      admin_conn
      |> recycle()
      |> put_req_header("content-type", "application/json")
      |> patch("/api/org/#{MilosTraining.Organizations.legacy_organization_slug()}/admin/workouts/#{draft_id}/draft", Jason.encode!(draft_payload))
      |> json_response(200)

      workout =
        admin_conn
        |> recycle()
        |> put_req_header("content-type", "application/json")
        |> post("/api/org/#{MilosTraining.Organizations.legacy_organization_slug()}/admin/workouts/#{draft_id}/publish", Jason.encode!(%{}))
        |> json_response(200)
        |> Map.fetch!("workout")

      assert workout["status"] == "published"
      assert workout["authoring_mode"] == "free_text"
      assert workout["free_text_body"] == "AMRAP 20\n10 pull-ups\n15 wall balls"
      assert workout["sections"] == []
      assert workout["available_scale_levels"] == []
    end

    test "publishes structured set composition and returns it without losing notes", %{conn: conn} do
      admin_conn = authenticate_as_admin(conn, "structured_set_author")

      draft_id =
        post(admin_conn, "/api/org/#{MilosTraining.Organizations.legacy_organization_slug()}/admin/workouts") |> json_response(201) |> get_in(["draft", "id"])

      superset_group_id = Ecto.UUID.generate()
      alternating_group_id = Ecto.UUID.generate()

      draft_payload = %{
        title: "Set Composition",
        type: "strength",
        sections: [
          %{
            name: "Main work",
            note: "Section note",
            timer_config: %{type: "for_time"},
            exercises: [
              %{item_type: "header", name: "Primary lifts", note: "Header note"},
              %{
                item_type: "exercise",
                name: "Front squat",
                note: "Stay upright",
                sets: 3,
                prescription_value: 8,
                prescription_unit: "reps",
                load_mode: "pct_1rm",
                load_progression: %{
                  mode: "linear",
                  direction: "decrease",
                  start_value: 80,
                  start_mode: "pct_1rm",
                  step_value: 5,
                  per_set_values: []
                },
                superset_group_id: superset_group_id
              },
              %{
                item_type: "exercise",
                name: "Pull-up",
                sets: 3,
                prescription_value: 6,
                prescription_unit: "reps",
                superset_group_id: superset_group_id
              },
              alternating_exercise("Row", alternating_group_id, [12, 10, 8]),
              alternating_exercise("Push-up", alternating_group_id, [10, 8, 6]),
              alternating_exercise("Lunge", alternating_group_id, [8, 6, 4])
            ]
          }
        ]
      }

      admin_conn
      |> recycle()
      |> put_req_header("content-type", "application/json")
      |> patch("/api/org/#{MilosTraining.Organizations.legacy_organization_slug()}/admin/workouts/#{draft_id}/draft", Jason.encode!(draft_payload))
      |> json_response(200)

      workout =
        admin_conn
        |> recycle()
        |> put_req_header("content-type", "application/json")
        |> post("/api/org/#{MilosTraining.Organizations.legacy_organization_slug()}/admin/workouts/#{draft_id}/publish", Jason.encode!(%{}))
        |> json_response(200)
        |> Map.fetch!("workout")

      [section] = workout["sections"]
      [header, squat, pull_up, row, push_up, lunge] = section["exercises"]

      assert section["note"] == "Section note"

      assert {header["item_type"], header["name"], header["note"]} ==
               {"header", "Primary lifts", "Header note"}

      assert squat["superset_group_id"] == superset_group_id
      assert pull_up["superset_group_id"] == superset_group_id
      assert squat["note"] == "Stay upright"
      assert Enum.map(squat["set_prescriptions"], & &1["load_value"]) == [80, 75, 70]
      assert Enum.map(row["set_prescriptions"], & &1["prescription_value"]) == [12, 10, 8]

      assert Enum.map([row, push_up, lunge], & &1["alternating_group_id"]) ==
               List.duplicate(alternating_group_id, 3)
    end
  end

  defp authenticate_as_admin(conn, nickname) do
    admin = create_admin!(nickname)
    put_bearer_token(conn, admin)
  end

  defp create_admin!(nickname) do
    {:ok, user} =
      Identity.register(%{
        nickname: nickname,
        password: "S3cur3P@ss!",
        role: :member
      })

    {:ok, admin} = Identity.update_role(user, :admin)
    {:ok, _membership} = Organizations.ensure_legacy_membership(admin, :owner)
    admin
  end

  defp alternating_exercise(name, group_id, reps) do
    %{
      item_type: "exercise",
      name: name,
      sets: length(reps),
      prescription_value: hd(reps),
      prescription_unit: "reps",
      alternating_group_id: group_id,
      set_prescriptions:
        reps
        |> Enum.with_index(1)
        |> Enum.map(fn {value, index} ->
          %{set_index: index, prescription_value: value, prescription_unit: "reps"}
        end)
    }
  end
end
