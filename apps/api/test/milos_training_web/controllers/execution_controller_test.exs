defmodule MilosTrainingWeb.ExecutionControllerTest do
  use MilosTrainingWeb.ConnCase, async: false

  import MilosTraining.TestFixtures, only: [slot_fixture: 2]

  alias MilosTraining.Application.SubmitBooking
  alias MilosTraining.Identity
  alias MilosTraining.Finance
  alias MilosTraining.Notifications
  alias MilosTraining.Workouts

  describe "execution ownership and lifecycle" do
    test "user cannot read another user's execution, but admin can", %{conn: conn} do
      admin = create_admin!("execution_admin_reader")
      owner_conn = authenticate_as_member(conn, "execution_owner")
      intruder_conn = authenticate_as_member(conn, "execution_intruder")

      workout = workout_with_scale!(admin)

      execution =
        owner_conn
        |> post("/api/executions", %{
          master_workout_id: workout.id,
          scale_level_slug: "scaled",
          source: "self_selected"
        })
        |> json_response(201)
        |> Map.fetch!("execution")

      intruder_response =
        intruder_conn
        |> get("/api/executions/#{execution["id"]}")
        |> json_response(404)

      assert intruder_response["error"] == "Not found"

      owner_response =
        owner_conn
        |> recycle()
        |> get("/api/executions/#{execution["id"]}")
        |> json_response(200)

      assert get_in(owner_response, ["execution", "id"]) == execution["id"]

      admin_response =
        put_bearer_token(conn, admin)
        |> get("/api/executions/#{execution["id"]}")
        |> json_response(200)

      assert get_in(admin_response, ["execution", "id"]) == execution["id"]
    end

    test "invalid scale level returns 422", %{conn: conn} do
      admin = create_admin!("execution_scale_admin")
      athlete_conn = authenticate_as_member(conn, "execution_scale_athlete")
      workout = workout_with_scale!(admin)

      response =
        athlete_conn
        |> post("/api/executions", %{
          master_workout_id: workout.id,
          scale_level_slug: "unknown",
          source: "self_selected"
        })
        |> json_response(422)

      assert response["error"] == "Invalid scale level"
    end

    test "inactive managed memberships cannot start workout execution", %{conn: conn} do
      admin = create_admin!("execution_entitlement_admin")

      {:ok, member} =
        Identity.register(%{
          nickname: "execution_inactive_athlete",
          password: "S3cur3P@ss!",
          role: :member
        })

      assert {:ok, _membership} =
               Finance.upsert_membership(member.id, %{
                 user_type_snapshot: "member",
                 status: "paused",
                 signup_source: "direct"
               })

      workout = workout_with_scale!(admin)

      response =
        conn
        |> put_bearer_token(member)
        |> post("/api/executions", %{
          master_workout_id: workout.id,
          scale_level_slug: "scaled",
          source: "self_selected"
        })
        |> json_response(403)

      assert response["error"] == "Finance entitlement inactive"
    end

    test "complete returns client errors for forbidden and already completed", %{conn: conn} do
      admin = create_admin!("execution_complete_admin")
      owner_conn = authenticate_as_member(conn, "execution_complete_owner")
      intruder_conn = authenticate_as_member(conn, "execution_complete_intruder")
      workout = workout_with_scale!(admin)

      execution_id =
        owner_conn
        |> post("/api/executions", %{
          master_workout_id: workout.id,
          scale_level_slug: "scaled",
          source: "self_selected"
        })
        |> json_response(201)
        |> get_in(["execution", "id"])

      forbidden_response =
        intruder_conn
        |> patch("/api/executions/#{execution_id}/complete", %{section_scores: []})
        |> json_response(403)

      assert forbidden_response["error"] == "Forbidden"

      completion_response =
        owner_conn
        |> recycle()
        |> patch("/api/executions/#{execution_id}/complete", %{section_scores: []})
        |> json_response(200)

      assert get_in(completion_response, ["execution", "id"]) == execution_id

      repeat_response =
        owner_conn
        |> recycle()
        |> patch("/api/executions/#{execution_id}/complete", %{section_scores: []})
        |> json_response(409)

      assert repeat_response["error"] == "Execution already completed"
    end

    test "athlete execution and timer access require a matching assignment", %{conn: conn} do
      admin = create_admin!("execution_assignment_admin")
      athlete = create_user!(:athlete, "execution_assigned_athlete")
      other_athlete = create_user!(:athlete, "execution_other_athlete")
      athlete_conn = put_bearer_token(conn, athlete)
      workout = workout_with_scale!(admin)

      assert {:ok, assignment} =
               Workouts.assign_workout(%{
                 master_workout_id: workout.id,
                 scheduled_for: Date.utc_today(),
                 athlete_ids: [athlete.id]
               })

      forbidden =
        athlete_conn
        |> post("/api/executions", %{
          master_workout_id: workout.id,
          source: "self_selected"
        })
        |> json_response(403)

      assert forbidden["error"] == "Workout execution source is not authorized"

      mismatched =
        conn
        |> recycle()
        |> put_bearer_token(other_athlete)
        |> post("/api/executions", %{
          master_workout_id: workout.id,
          source: "assigned",
          source_reference_id: assignment.id
        })
        |> json_response(403)

      assert mismatched["error"] == "Workout execution source is not authorized"

      execution =
        athlete_conn
        |> recycle()
        |> post("/api/executions", %{
          master_workout_id: workout.id,
          source: "assigned",
          source_reference_id: assignment.id
        })
        |> json_response(201)

      assert execution["execution"]["source_reference_id"] == assignment.id

      athlete_conn
      |> recycle()
      |> get(
        "/api/workouts/#{workout.id}/timer-sequence?source=assigned&source_reference_id=#{assignment.id}"
      )
      |> json_response(200)

      conn
      |> recycle()
      |> put_bearer_token(other_athlete)
      |> get(
        "/api/workouts/#{workout.id}/timer-sequence?source=assigned&source_reference_id=#{assignment.id}"
      )
      |> json_response(403)
    end

    test "member execution and timer access require an approved matching class booking", %{
      conn: conn
    } do
      admin = create_admin!("execution_booking_admin")
      member = create_user!(:member, "execution_booked_member")
      other_member = create_user!(:member, "execution_other_member")
      workout = workout_with_scale!(admin)
      slot = slot_fixture(workout, %{auto_approve: true})

      assert {:ok, booking} = SubmitBooking.call(member.id, slot.id)
      assert booking.status == :approved

      execution =
        conn
        |> put_bearer_token(member)
        |> post("/api/executions", %{
          master_workout_id: workout.id,
          source: "class_booking",
          source_reference_id: booking.id
        })
        |> json_response(201)

      assert execution["execution"]["source_reference_id"] == booking.id

      conn
      |> recycle()
      |> put_bearer_token(member)
      |> get(
        "/api/workouts/#{workout.id}/timer-sequence?source=class_booking&source_reference_id=#{booking.id}"
      )
      |> json_response(200)

      conn
      |> recycle()
      |> put_bearer_token(other_member)
      |> get(
        "/api/workouts/#{workout.id}/timer-sequence?source=class_booking&source_reference_id=#{booking.id}"
      )
      |> json_response(403)
    end
  end

  describe "execution progress and notes" do
    test "progress persists checked exercise ids and auto progress snapshots for the owner", %{
      conn: conn
    } do
      admin = create_admin!("execution_progress_admin")
      athlete_conn = authenticate_as_member(conn, "execution_progress_athlete")
      workout = scoreable_for_time_workout!(admin)
      section_id = workout.sections |> hd() |> Map.fetch!(:id)
      exercise_id = workout.sections |> hd() |> Map.fetch!(:exercises) |> hd() |> Map.fetch!(:id)

      execution_id =
        athlete_conn
        |> post("/api/executions", %{
          master_workout_id: workout.id,
          scale_level_slug: "scaled",
          source: "self_selected"
        })
        |> json_response(201)
        |> get_in(["execution", "id"])

      execution_version =
        athlete_conn
        |> recycle()
        |> get("/api/executions/#{execution_id}")
        |> json_response(200)
        |> get_in(["execution", "lock_version"])

      response =
        athlete_conn
        |> recycle()
        |> patch("/api/executions/#{execution_id}/progress", %{
          expected_version: execution_version,
          operation_id: Ecto.UUID.generate(),
          checked_exercise_ids: ["segment:0::#{exercise_id}::set:1"],
          current_segment_index: 0,
          status: "active",
          paused_elapsed_ms: 0,
          total_elapsed_ms: 120_000,
          section_elapsed_ms: %{section_id => 120_000},
          segment_cycle_counts: %{}
        })
        |> json_response(200)

      assert response["execution"]["checked_exercise_ids"] == ["segment:0::#{exercise_id}::set:1"]

      assert response["execution"]["section_scores"] == [
               %{
                 "kind" => "progress",
                 "score_type" => "reps",
                 "section_id" => section_id,
                 "source" => "auto",
                 "unit" => "reps",
                 "value" => 8
               }
             ]
    end

    test "progress rejects stale writes and semantic state outside the timer sequence", %{
      conn: conn
    } do
      admin = create_admin!("execution_integrity_admin")
      athlete_conn = authenticate_as_member(conn, "execution_integrity_athlete")
      workout = scoreable_for_time_workout!(admin)

      execution =
        athlete_conn
        |> post("/api/executions", %{
          master_workout_id: workout.id,
          scale_level_slug: "scaled",
          source: "self_selected"
        })
        |> json_response(201)
        |> Map.fetch!("execution")

      valid = %{
        expected_version: execution["lock_version"],
        operation_id: Ecto.UUID.generate(),
        checked_exercise_ids: [],
        current_segment_index: 0,
        status: "paused",
        paused_elapsed_ms: 1_000,
        total_elapsed_ms: 1_000,
        section_elapsed_ms: %{},
        segment_cycle_counts: %{}
      }

      updated =
        athlete_conn
        |> recycle()
        |> patch("/api/executions/#{execution["id"]}/progress", valid)
        |> json_response(200)
        |> Map.fetch!("execution")

      assert updated["lock_version"] == execution["lock_version"] + 1

      replayed =
        athlete_conn
        |> recycle()
        |> patch("/api/executions/#{execution["id"]}/progress", valid)
        |> json_response(200)
        |> Map.fetch!("execution")

      assert replayed["lock_version"] == updated["lock_version"]
      assert replayed["status"] == updated["status"]

      athlete_conn
      |> recycle()
      |> patch(
        "/api/executions/#{execution["id"]}/progress",
        Map.put(valid, :operation_id, Ecto.UUID.generate())
      )
      |> json_response(409)

      athlete_conn
      |> recycle()
      |> patch("/api/executions/#{execution["id"]}/progress", %{
        valid
        | expected_version: updated["lock_version"],
          operation_id: Ecto.UUID.generate(),
          current_segment_index: 999,
          checked_exercise_ids: ["forged-step"],
          total_elapsed_ms: 9_999_999_999,
          section_elapsed_ms: %{Ecto.UUID.generate() => 42},
          segment_cycle_counts: %{forged: 42}
      })
      |> json_response(400)
    end

    test "completion persists measured fallback scores when none are submitted manually", %{
      conn: conn
    } do
      admin = create_admin!("execution_complete_score_admin")
      athlete_conn = authenticate_as_member(conn, "exec_complete_score")
      workout = scoreable_for_time_workout!(admin)
      section_id = workout.sections |> hd() |> Map.fetch!(:id)
      exercise_id = workout.sections |> hd() |> Map.fetch!(:exercises) |> hd() |> Map.fetch!(:id)

      execution_id =
        athlete_conn
        |> post("/api/executions", %{
          master_workout_id: workout.id,
          scale_level_slug: "scaled",
          source: "self_selected"
        })
        |> json_response(201)
        |> get_in(["execution", "id"])

      response =
        athlete_conn
        |> recycle()
        |> patch("/api/executions/#{execution_id}/complete", %{
          checked_exercise_ids: [
            "segment:0::#{exercise_id}::set:1",
            "segment:0::#{exercise_id}::set:2"
          ],
          total_elapsed_ms: 120_000,
          section_elapsed_ms: %{section_id => 120_000},
          segment_cycle_counts: %{}
        })
        |> json_response(200)

      assert response["execution"]["section_scores"] == [
               %{
                 "kind" => "final",
                 "score_type" => "time",
                 "section_id" => section_id,
                 "source" => "auto",
                 "value" => "2:00"
               }
             ]
    end

    test "completion rejects scores for unknown or mismatched sections", %{conn: conn} do
      admin = create_admin!("score_validation_admin")
      athlete_conn = authenticate_as_member(conn, "score_validation_member")
      workout = scoreable_for_time_workout!(admin)
      section_id = workout.sections |> hd() |> Map.fetch!(:id)

      execution_id =
        athlete_conn
        |> post("/api/executions", %{
          master_workout_id: workout.id,
          scale_level_slug: "scaled",
          source: "self_selected"
        })
        |> json_response(201)
        |> get_in(["execution", "id"])

      athlete_conn
      |> recycle()
      |> patch("/api/executions/#{execution_id}/complete", %{
        section_scores: [
          %{section_id: Ecto.UUID.generate(), score_type: "reps", value: 999_999}
        ]
      })
      |> json_response(400)

      athlete_conn
      |> recycle()
      |> patch("/api/executions/#{execution_id}/complete", %{
        section_scores: [%{section_id: section_id, score_type: "reps", value: 999_999}]
      })
      |> json_response(400)
    end

    test "submitting a note persists it and creates admin notifications", %{conn: conn} do
      admin = create_admin!("execution_note_admin")
      athlete_conn = authenticate_as_member(conn, "execution_note_athlete")
      workout = workout_with_scale!(admin)

      exercise_id =
        workout.id
        |> Workouts.materialize_workout_for_scale("scaled")
        |> Map.fetch!(:sections)
        |> hd()
        |> Map.fetch!(:exercises)
        |> hd()
        |> Map.fetch!(:id)

      execution_id =
        athlete_conn
        |> post("/api/executions", %{
          master_workout_id: workout.id,
          scale_level_slug: "scaled",
          source: "self_selected"
        })
        |> json_response(201)
        |> get_in(["execution", "id"])

      response =
        athlete_conn
        |> recycle()
        |> post("/api/executions/#{execution_id}/notes", %{
          exercise_id: exercise_id,
          selected_text: "Thruster",
          selection_start: 0,
          selection_end: 8,
          tags: ["form"],
          note_text: "Needed more rest"
        })
        |> json_response(200)

      assert response["execution"]["exercise_notes"] == [
               %{
                 "exercise_id" => exercise_id,
                 "id" => response["execution"]["exercise_notes"] |> hd() |> Map.fetch!("id"),
                 "inserted_at" =>
                   response["execution"]["exercise_notes"] |> hd() |> Map.fetch!("inserted_at"),
                 "note_text" => "Needed more rest",
                 "selected_text" => "Thruster",
                 "selection_end" => 8,
                 "selection_start" => 0,
                 "tags" => ["form"],
                 "updated_at" =>
                   response["execution"]["exercise_notes"] |> hd() |> Map.fetch!("updated_at")
               }
             ]

      notifications = wait_for_notifications(admin.id)

      assert Enum.any?(notifications, fn notification ->
               notification.type == "workout_note" and
                 notification.payload["execution_id"] == execution_id and
                 get_in(notification.payload, ["note", "selected_text"]) == "Thruster"
             end)
    end

    test "submitting a note rejects exercises and text ranges outside the workout", %{conn: conn} do
      admin = create_admin!("note_validation_admin")
      athlete_conn = authenticate_as_member(conn, "note_validation_member")
      workout = workout_with_scale!(admin)
      exercise_id = workout.sections |> hd() |> Map.fetch!(:exercises) |> hd() |> Map.fetch!(:id)

      execution_id =
        athlete_conn
        |> post("/api/executions", %{
          master_workout_id: workout.id,
          scale_level_slug: "scaled",
          source: "self_selected"
        })
        |> json_response(201)
        |> get_in(["execution", "id"])

      athlete_conn
      |> recycle()
      |> post("/api/executions/#{execution_id}/notes", %{
        exercise_id: Ecto.UUID.generate(),
        selected_text: "Thruster",
        selection_start: 0,
        selection_end: 8,
        tags: ["form"]
      })
      |> json_response(400)

      athlete_conn
      |> recycle()
      |> post("/api/executions/#{execution_id}/notes", %{
        exercise_id: exercise_id,
        selected_text: "Not the label",
        selection_start: 0,
        selection_end: 8,
        tags: ["form"]
      })
      |> json_response(400)
    end
  end

  defp wait_for_notifications(user_id, attempts \\ 10)

  defp wait_for_notifications(user_id, attempts) when attempts > 0 do
    notifications = Notifications.list_for_user(user_id)

    if notifications == [] do
      Process.sleep(20)
      wait_for_notifications(user_id, attempts - 1)
    else
      notifications
    end
  end

  defp wait_for_notifications(user_id, 0), do: Notifications.list_for_user(user_id)

  defp workout_with_scale!(admin) do
    :ok = ensure_scale_level!("scaled", "Scaled")

    {:ok, workout} =
      Workouts.create_workout(admin, %{
        title: "Execution Workout",
        type: "crossfit",
        sections: [
          %{
            name: "Main Set",
            order: 1,
            scoreable: false,
            exercises: [
              %{
                name: "Thruster",
                order: 1,
                prescription_value: 12,
                prescription_unit: "reps",
                variations: [
                  %{
                    scale_level_slug: "scaled",
                    prescription_value: 8
                  }
                ]
              }
            ]
          }
        ]
      })

    workout
  end

  defp scoreable_for_time_workout!(admin) do
    :ok = ensure_scale_level!("scaled", "Scaled")

    {:ok, workout} =
      Workouts.create_workout(admin, %{
        title: "Measured For Time",
        type: "crossfit",
        sections: [
          %{
            name: "Main Set",
            order: 1,
            scoreable: true,
            score_config: %{type: "time", unit: "sec", label: "Time"},
            timer_config: %{type: "for_time"},
            exercises: [
              %{
                name: "Thruster",
                order: 1,
                sets: 2,
                prescription_value: 10,
                prescription_unit: "reps",
                variations: [
                  %{
                    scale_level_slug: "scaled",
                    prescription_value: 8
                  }
                ]
              }
            ]
          }
        ]
      })

    workout
  end

  defp ensure_scale_level!(slug, label) do
    levels = Workouts.list_scale_levels()

    if Enum.any?(levels, &(&1.slug == slug)) do
      :ok
    else
      new_level = %{slug: slug, label: label, sort_order: length(levels) + 1}

      {:ok, _levels} =
        Workouts.replace_scale_levels(
          levels
          |> Enum.map(fn level ->
            %{slug: level.slug, label: level.label, sort_order: level.sort_order}
          end)
          |> Kernel.++([new_level])
        )

      :ok
    end
  end

  defp authenticate_as_member(conn, nickname) do
    put_bearer_token(conn, create_user!(:member, nickname))
  end

  defp create_user!(role, nickname) do
    {:ok, user} =
      Identity.register(%{nickname: nickname, password: "S3cur3P@ss!", role: role})

    user
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
