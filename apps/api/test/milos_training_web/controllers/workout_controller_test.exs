defmodule MilosTrainingWeb.WorkoutControllerTest do
  use MilosTrainingWeb.ConnCase, async: false

  alias MilosTraining.Identity
  alias MilosTraining.Infrastructure.Auth.Guardian

  describe "member workout queries" do
    test "member can view a workout and its materialized scales", %{conn: conn} do
      admin = create_admin!("admin_view_workout")
      member_conn = authenticate_as_member(conn, "member_view_workout")

      {:ok, _levels} =
        MilosTraining.Workouts.replace_scale_levels([
          %{slug: "scaled", label: "Scaled", sort_order: 1},
          %{slug: "rx", label: "Rx", sort_order: 2},
          %{slug: "competition", label: "Competition", sort_order: 3}
        ])

      {:ok, workout} =
        MilosTraining.Workouts.create_workout(admin, %{
          title: "Pull-up Sprint",
          type: "gymnastics",
          sections: [
            %{
              name: "Ladder",
              order: 1,
              exercises: [
                %{
                  name: "Pull-ups",
                  sets: 1,
                  prescription_value: 10,
                  prescription_unit: "reps",
                  order: 1,
                  variations: [
                    %{
                      scale_level_slug: "scaled",
                      prescription_value: 6,
                      exercise_name_override: "Ring rows"
                    },
                    %{
                      scale_level_slug: "competition",
                      prescription_value: 12,
                      exercise_name_override: "Chest to bar"
                    }
                  ]
                }
              ]
            }
          ]
        })

      show_conn = get(member_conn, "/api/workouts/#{workout.id}")
      show_payload = json_response(show_conn, 200)["workout"]

      assert show_payload["title"] == "Pull-up Sprint"

      scales_conn = get(member_conn |> recycle(), "/api/workouts/#{workout.id}/scales")
      scales_payload = json_response(scales_conn, 200)

      assert Enum.map(scales_payload["scales"], &get_in(&1, ["scale_level", "slug"])) == [
               "scaled",
               "competition"
             ]

      scaled_instance =
        Enum.find(scales_payload["scales"], &(get_in(&1, ["scale_level", "slug"]) == "scaled"))

      [section] = scaled_instance["sections"]
      [exercise] = section["exercises"]

      assert exercise["prescription_value"] == 6
      assert exercise["name"] == "Ring rows"
    end

    test "athletes are forbidden from reading member workout discovery endpoints", %{conn: conn} do
      admin = create_admin!("admin_forbidden_workout")
      athlete_conn = authenticate_as_athlete(conn, "athlete_blocked_workout")

      {:ok, _levels} =
        MilosTraining.Workouts.replace_scale_levels([
          %{slug: "scaled", label: "Scaled", sort_order: 1}
        ])

      {:ok, workout} =
        MilosTraining.Workouts.create_workout(admin, %{
          title: "Members Only",
          type: "gymnastics",
          sections: [
            %{
              name: "Warm-up",
              order: 1,
              exercises: [
                %{name: "Band Pull Aparts", order: 1, variations: []}
              ]
            }
          ]
        })

      assert (athlete_conn
              |> get("/api/workouts/#{workout.id}")
              |> json_response(403))["error"] == "Forbidden"

      assert (athlete_conn
              |> recycle()
              |> get("/api/workouts/#{workout.id}/scales")
              |> json_response(403))["error"] == "Forbidden"
    end
  end

  defp authenticate_as_member(conn, nickname) do
    {:ok, member} =
      Identity.register(%{
        nickname: nickname,
        password: "S3cur3P@ss!",
        role: :member
      })

    put_bearer_token(conn, member)
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

  defp authenticate_as_athlete(conn, nickname) do
    {:ok, athlete} =
      Identity.register(%{
        nickname: nickname,
        password: "S3cur3P@ss!",
        role: :athlete
      })

    put_bearer_token(conn, athlete)
  end

  defp put_bearer_token(conn, user) do
    {:ok, token, _claims} = Guardian.encode_and_sign(user, %{}, token_type: "access")
    put_req_header(conn, "authorization", "Bearer " <> token)
  end
end
