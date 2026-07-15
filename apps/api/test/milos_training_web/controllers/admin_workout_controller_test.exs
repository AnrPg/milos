defmodule MilosTrainingWeb.AdminWorkoutControllerTest do
  use MilosTrainingWeb.ConnCase, async: false

  alias MilosTraining.Identity

  describe "admin workout draft flow" do
    test "admin can create, autosave, inspect, and publish a draft", %{conn: conn} do
      admin_conn = authenticate_as_admin(conn, "admin_draft_author")

      {:ok, _levels} =
        MilosTraining.Workouts.replace_scale_levels([
          %{slug: "scaled", label: "Scaled", sort_order: 1},
          %{slug: "rx", label: "Rx", sort_order: 2},
          %{slug: "competition", label: "Competition", sort_order: 3}
        ])

      create_conn = post(admin_conn, "/api/admin/workouts")
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
        |> patch("/api/admin/workouts/#{draft_id}/draft", Jason.encode!(draft_payload))

      assert json_response(autosave_conn, 200)["draft"]["status"] == "draft"

      show_conn = get(admin_conn |> recycle(), "/api/admin/workouts/#{draft_id}")
      shown_workout = json_response(show_conn, 200)["workout"]

      assert shown_workout["status"] == "draft"
      assert shown_workout["draft_data"]["title"] == "Engine Ladder"

      publish_conn =
        admin_conn
        |> recycle()
        |> put_req_header("content-type", "application/json")
        |> post("/api/admin/workouts/#{draft_id}/publish", Jason.encode!(%{}))

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
      create_conn = post(admin_conn, "/api/admin/workouts")
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
        |> patch("/api/admin/workouts/#{draft_id}/draft", Jason.encode!(draft_payload))

      assert json_response(autosave_conn, 200)["draft"]["id"] == draft_id

      publish_conn =
        admin_conn
        |> recycle()
        |> put_req_header("content-type", "application/json")
        |> post("/api/admin/workouts/#{draft_id}/publish", Jason.encode!(%{}))

      assert json_response(publish_conn, 200)["workout"]["status"] == "published"
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
    admin
  end
end
