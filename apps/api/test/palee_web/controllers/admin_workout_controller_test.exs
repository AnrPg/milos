defmodule PaleeWeb.AdminWorkoutControllerTest do
  use PaleeWeb.ConnCase, async: false

  alias Palee.{Identity, Organizations}

  describe "admin workout draft flow" do
    test "admin can create, autosave, inspect, and publish a draft", %{conn: conn} do
      {admin_conn, organization} = authenticate_as_admin(conn, "admin_draft_author")

      {:ok, _levels} =
        Palee.Workouts.replace_scale_levels(%{organization_id: organization.id}, [
          %{slug: "scaled", label: "Scaled", sort_order: 1},
          %{slug: "rx", label: "Rx", sort_order: 2},
          %{slug: "competition", label: "Competition", sort_order: 3}
        ])

      create_conn =
        post(
          admin_conn,
          "/api/org/#{organization.slug}/admin/workouts"
        )

      draft = json_response(create_conn, 201)["draft"]
      draft_id = draft["id"]

      assert draft["status"] == "draft"

      draft_payload = %{
        title: "Engine Ladder",
        type: "crossfit",
        expected_source_revision: 0,
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
        |> patch(
          "/api/org/#{organization.slug}/admin/workouts/#{draft_id}/draft",
          Jason.encode!(draft_payload)
        )

      assert json_response(autosave_conn, 200)["draft"]["status"] == "draft"

      show_conn =
        get(
          admin_conn |> recycle(),
          "/api/org/#{organization.slug}/admin/workouts/#{draft_id}"
        )

      shown_workout = json_response(show_conn, 200)["workout"]

      assert shown_workout["status"] == "draft"
      assert shown_workout["draft_data"]["title"] == "Engine Ladder"

      publish_conn =
        admin_conn
        |> recycle()
        |> put_req_header("content-type", "application/json")
        |> post(
          "/api/org/#{organization.slug}/admin/workouts/#{draft_id}/publish",
          Jason.encode!(%{expected_source_revision: 1})
        )

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

    test "admin can delete a draft without surfacing a post-delete broadcast error", %{conn: conn} do
      {admin_conn, organization} = authenticate_as_admin(conn, "admin_draft_deleter")

      draft_id =
        admin_conn
        |> post("/api/org/#{organization.slug}/admin/workouts")
        |> json_response(201)
        |> get_in(["draft", "id"])

      delete_conn =
        admin_conn
        |> recycle()
        |> delete("/api/org/#{organization.slug}/admin/workouts/#{draft_id}")

      assert response(delete_conn, 204) == ""

      admin_conn
      |> recycle()
      |> get("/api/org/#{organization.slug}/admin/workouts/#{draft_id}")
      |> json_response(404)
    end

    test "publishes a container whose exercises are in nested child sections", %{conn: conn} do
      {admin_conn, organization} = authenticate_as_admin(conn, "nested_draft_author")

      create_conn =
        post(
          admin_conn,
          "/api/org/#{organization.slug}/admin/workouts"
        )

      draft_id = json_response(create_conn, 201)["draft"]["id"]

      draft_payload = %{
        title: "Nested Strength",
        type: "strength",
        expected_source_revision: 0,
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
        |> patch(
          "/api/org/#{organization.slug}/admin/workouts/#{draft_id}/draft",
          Jason.encode!(draft_payload)
        )

      assert json_response(autosave_conn, 200)["draft"]["id"] == draft_id

      publish_conn =
        admin_conn
        |> recycle()
        |> put_req_header("content-type", "application/json")
        |> post(
          "/api/org/#{organization.slug}/admin/workouts/#{draft_id}/publish",
          Jason.encode!(%{expected_source_revision: 1})
        )

      assert json_response(publish_conn, 200)["workout"]["status"] == "published"
    end

    test "publishes a free-text workout without structured sections", %{conn: conn} do
      {admin_conn, organization} = authenticate_as_admin(conn, "free_text_author")

      draft_id =
        post(
          admin_conn,
          "/api/org/#{organization.slug}/admin/workouts"
        )
        |> json_response(201)
        |> get_in(["draft", "id"])

      draft_payload = %{
        title: "Friday Board WOD",
        type: "crossfit",
        authoring_mode: "free_text",
        expected_source_revision: 0,
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
      |> patch(
        "/api/org/#{organization.slug}/admin/workouts/#{draft_id}/draft",
        Jason.encode!(draft_payload)
      )
      |> json_response(200)

      workout =
        admin_conn
        |> recycle()
        |> put_req_header("content-type", "application/json")
        |> post(
          "/api/org/#{organization.slug}/admin/workouts/#{draft_id}/publish",
          Jason.encode!(%{expected_source_revision: 1})
        )
        |> json_response(200)
        |> Map.fetch!("workout")

      assert workout["status"] == "published"
      assert workout["authoring_mode"] == "free_text"
      assert workout["free_text_body"] == "AMRAP 20\n10 pull-ups\n15 wall balls"
      assert workout["sections"] == []

      assert %{
               "kind" => "free_text",
               "text" => "AMRAP 20\n10 pull-ups\n15 wall balls",
               "document" => %{"type" => "doc"},
               "structured" => false
             } = workout["body"]

      assert workout["available_scale_levels"] == []
    end

    test "ADR-180: publishes a workout written in text sections, a timer each", %{conn: conn} do
      {admin_conn, organization} = authenticate_as_admin(conn, "sectioned_text_author")
      base = "/api/org/#{organization.slug}/admin/workouts"

      draft_id =
        admin_conn |> post(base) |> json_response(201) |> get_in(["draft", "id"])

      sections = [
        %{
          name: "Strength",
          order: 1,
          exercises: [],
          free_text_body: "Back squat 5x5 @ 75%",
          timer_preset: %{format: "emom", interval_seconds: 120, rounds: 5}
        },
        %{
          name: "",
          order: 2,
          exercises: [],
          free_text_body: "21-15-9\nThrusters\nPull-ups",
          timer_preset: nil
        }
      ]

      draft_payload = %{
        title: "Sectioned Friday",
        type: "crossfit",
        authoring_mode: "sectioned_text",
        expected_source_revision: 0,
        sections: sections
      }

      admin_conn
      |> recycle()
      |> put_req_header("content-type", "application/json")
      |> patch("#{base}/#{draft_id}/draft", Jason.encode!(draft_payload))
      |> json_response(200)

      # The second section has no timer yet: publishing names it.
      rejected =
        admin_conn
        |> recycle()
        |> put_req_header("content-type", "application/json")
        |> post("#{base}/#{draft_id}/publish", Jason.encode!(%{expected_source_revision: 1}))
        |> json_response(422)

      assert rejected["code"] == "invalid_text_sections"
      assert rejected["details"]["sections"] == [%{"section" => 2, "problem" => "timer_required"}]

      timed =
        List.update_at(
          sections,
          1,
          &Map.put(&1, :timer_preset, %{format: "for_time", duration_seconds: 900})
        )

      workout =
        admin_conn
        |> recycle()
        |> put_req_header("content-type", "application/json")
        |> post(
          "#{base}/#{draft_id}/publish",
          Jason.encode!(%{expected_source_revision: 1, sections: timed})
        )
        |> json_response(200)
        |> Map.fetch!("workout")

      assert workout["authoring_mode"] == "sectioned_text"

      assert workout["free_text_body"] ==
               "Strength\nBack squat 5x5 @ 75%\n\n21-15-9\nThrusters\nPull-ups"

      assert [
               %{"name" => "Strength", "timer_preset" => %{"format" => "emom", "rounds" => 5}},
               %{
                 "name" => "2",
                 "free_text_body" => "21-15-9\nThrusters\nPull-ups",
                 "timer_preset" => %{"format" => "for_time", "duration_seconds" => 900},
                 "section_metadata" => %{"untitled" => true},
                 "exercises" => []
               }
             ] = workout["sections"]

      # ADR-223: the body carries only what text sections have.
      assert %{
               "kind" => "text_sections",
               "sections" => [
                 %{
                   "title" => "Strength",
                   "text" => "Back squat 5x5 @ 75%",
                   "timer" => %{"format" => "emom", "rounds" => 5},
                   "scoring" => []
                 },
                 %{
                   "title" => nil,
                   "text" => "21-15-9\nThrusters\nPull-ups",
                   "document" => %{"type" => "doc"}
                 }
               ]
             } = workout["body"]

      listed =
        admin_conn
        |> recycle()
        |> get(base)
        |> json_response(200)
        |> Map.fetch!("workouts")
        |> Enum.find(&(&1["id"] == draft_id))

      assert %{
               "kind" => "text_sections",
               "sections" => [
                 %{"title" => "Strength", "excerpt" => "Back squat 5x5 @ 75%", "scored" => false},
                 %{"title" => nil, "excerpt" => "21-15-9\nThrusters\nPull-ups"}
               ]
             } = listed["body"]

      refute Map.has_key?(hd(listed["body"]["sections"]), "document")
    end

    test "publishes a free-text workout with assistant-derived canonical sections", %{conn: conn} do
      {admin_conn, organization} = authenticate_as_admin(conn, "free_text_ai_publisher")

      draft_id =
        post(admin_conn, "/api/org/#{organization.slug}/admin/workouts")
        |> json_response(201)
        |> get_in(["draft", "id"])

      body = "For time, cap 20\n5 rounds\n10 pull-ups\n20 push-ups\nBack squat 5x5 @ 100 kg"

      # Same shape FreeTextAnalysis.normalize/2 returns for "workout".
      payload = %{
        title: "Murph prep",
        type: "crossfit",
        difficulty: "intermediate",
        estimated_duration_seconds: 1500,
        equipment: ["pull-up bar", "barbell"],
        tags: [],
        subtitle: nil,
        description: nil,
        workout_metadata: %{timer_inference: "complete"},
        authoring_mode: "free_text",
        expected_source_revision: 0,
        free_text_body: body,
        sections: [
          %{
            name: "Main",
            note: nil,
            timer_config: %{"type" => "for_time", "rounds" => 5, "time_cap_seconds" => 1200},
            exercises: [
              %{
                "name" => "Pull-up",
                "item_type" => "exercise",
                "prescription_value" => 10,
                "prescription_unit" => "reps",
                "load_value" => nil,
                "load_mode" => nil,
                "sets" => nil,
                "rest_seconds" => nil,
                "tempo" => nil,
                "note" => nil
              },
              %{
                "name" => "Push-up",
                "item_type" => "exercise",
                "prescription_value" => 20,
                "prescription_unit" => "reps",
                "load_value" => nil,
                "load_mode" => "bw"
              }
            ]
          },
          %{
            name: "Strength",
            note: nil,
            timer_config: nil,
            exercises: [
              %{
                "name" => "Back squat",
                "item_type" => "exercise",
                "sets" => 5,
                "prescription_value" => 5,
                "prescription_unit" => "reps",
                "load_value" => 100,
                "load_mode" => "absolute",
                "rest_seconds" => 120
              }
            ]
          }
        ]
      }

      admin_conn
      |> recycle()
      |> put_req_header("content-type", "application/json")
      |> patch(
        "/api/org/#{organization.slug}/admin/workouts/#{draft_id}/draft",
        Jason.encode!(Map.put(payload, :draft_data, payload))
      )
      |> json_response(200)

      workout =
        admin_conn
        |> recycle()
        |> put_req_header("content-type", "application/json")
        |> post(
          "/api/org/#{organization.slug}/admin/workouts/#{draft_id}/publish",
          Jason.encode!(Map.put(payload, :expected_source_revision, 1))
        )
        |> json_response(200)
        |> Map.fetch!("workout")

      assert workout["status"] == "published"
      assert workout["authoring_mode"] == "free_text"
      assert workout["free_text_body"] == body
      assert workout["difficulty"] == "intermediate"
      assert workout["equipment"] == ["pull-up bar", "barbell"]
      assert workout["workout_metadata"]["timer_inference"] == "complete"
      assert [main, strength] = workout["sections"]
      assert main["timer_config"]["time_cap_seconds"] == 1200
      assert length(main["exercises"]) == 2
      assert [%{"name" => "Back squat", "load_value" => 100}] = strength["exercises"]
    end

    test "publishes structured set composition and returns it without losing notes", %{conn: conn} do
      {admin_conn, organization} = authenticate_as_admin(conn, "structured_set_author")

      draft_id =
        post(
          admin_conn,
          "/api/org/#{organization.slug}/admin/workouts"
        )
        |> json_response(201)
        |> get_in(["draft", "id"])

      superset_group_id = Ecto.UUID.generate()
      alternating_group_id = Ecto.UUID.generate()

      draft_payload = %{
        title: "Set Composition",
        type: "strength",
        expected_source_revision: 0,
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
      |> patch(
        "/api/org/#{organization.slug}/admin/workouts/#{draft_id}/draft",
        Jason.encode!(draft_payload)
      )
      |> json_response(200)

      workout =
        admin_conn
        |> recycle()
        |> put_req_header("content-type", "application/json")
        |> post(
          "/api/org/#{organization.slug}/admin/workouts/#{draft_id}/publish",
          Jason.encode!(%{expected_source_revision: 1})
        )
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
    {admin, organization} = create_admin!(nickname)
    {put_bearer_token(conn, admin), organization}
  end

  defp create_admin!(nickname) do
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

    {admin, organization}
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
