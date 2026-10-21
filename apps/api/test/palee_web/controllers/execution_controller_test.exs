defmodule PaleeWeb.ExecutionControllerTest do
  # TD-046: /api/executions is user-scoped, so tenant derivation must work
  # under the RLS-enforcing runtime role, not only as a superuser.
  use PaleeWeb.ConnCase, async: false

  import Palee.TestFixtures, only: [slot_fixture: 2]

  alias Palee.Application.SubmitBooking
  alias Palee.Identity
  alias Palee.Finance
  alias Palee.Notifications
  alias Palee.Organizations
  alias Palee.Workouts

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

    test "a client-supplied organization_id is ignored in favour of the workout's own", %{
      conn: conn
    } do
      admin = create_admin!("execution_forgery_admin")
      member = create_user!(:member, "execution_forgery_member")
      workout = workout_with_scale!(admin)

      {:ok, other_org} =
        Palee.Organizations.create_organization(%{name: "Execution Forgery Gym"})

      execution =
        conn
        |> put_bearer_token(member)
        |> post("/api/executions", %{
          master_workout_id: workout.id,
          scale_level_slug: "scaled",
          source: "self_selected",
          organization_id: other_org.id
        })
        |> json_response(201)
        |> Map.fetch!("execution")

      # F-03: the persisted organization is derived from the workout, never
      # from the request body.
      refute execution["organization_id"] == other_org.id

      assert execution["organization_id"] ==
               Palee.Workouts.WorkoutStore.workout_organization_id(workout.id)
    end

    test "self-selection is refused for an account with no membership in the workout's gym", %{
      conn: conn
    } do
      admin = create_admin!("execution_outsider_admin")
      workout = workout_with_scale!(admin)

      {:ok, outsider} =
        Identity.register(%{
          nickname: "execution_outsider",
          password: "S3cur3P@ss!42",
          role: :member,
          email: "u#{System.unique_integer([:positive])}@placeholder.invalid"
        })

      response =
        conn
        |> put_bearer_token(outsider)
        |> post("/api/executions", %{
          master_workout_id: workout.id,
          scale_level_slug: "scaled",
          source: "self_selected"
        })
        |> json_response(403)

      assert response["code"] == "execution_source_forbidden"
    end

    test "inactive managed memberships cannot start workout execution", %{conn: conn} do
      admin = create_admin!("execution_entitlement_admin")

      {:ok, member} =
        Identity.register(%{
          nickname: "execution_inactive_athlete",
          password: "S3cur3P@ss!42",
          role: :member,
          email: "u#{System.unique_integer([:positive])}@placeholder.invalid"
        })

      # Needs an organization membership to reach the entitlement check at all
      # (F-03); the assertion below is about finance entitlement, not tenancy.
      {:ok, _org_membership} = Organizations.ensure_legacy_membership_for_migration(member)

      {:ok, finance_context} =
        Organizations.resolve_tenant_context(member, Organizations.legacy_organization_slug())

      assert {:ok, _membership} =
               Finance.upsert_membership(finance_context, member.id, %{
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

    test "assigned execution uses the tenant membership instead of the account-wide role", %{
      conn: conn
    } do
      admin = create_admin!("exec_assign_tenant_admin")
      athlete = create_user!(:member, "exec_assign_tenant_athlete")
      workout = workout_with_scale!(admin)

      {:ok, admin_context} =
        Organizations.resolve_tenant_context(admin, Organizations.legacy_organization_slug())

      assert {:ok, _membership} =
               Organizations.set_membership_role(admin_context, athlete.id, :athlete)

      assert {:ok, assignment} =
               Workouts.assign_workout(admin_context, %{
                 master_workout_id: workout.id,
                 scheduled_for: Date.utc_today(),
                 athlete_ids: [athlete.id]
               })

      response =
        conn
        |> put_bearer_token(athlete)
        |> post("/api/executions", %{
          master_workout_id: workout.id,
          source: "assigned",
          source_reference_id: assignment.id
        })
        |> json_response(201)

      assert get_in(response, ["execution", "source_reference_id"]) == assignment.id
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

      {:ok, admin_context} =
        Organizations.resolve_tenant_context(admin, Organizations.legacy_organization_slug())

      assert {:ok, assignment} =
               Workouts.assign_workout(admin_context, %{
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

      {:ok, member_context} =
        Organizations.resolve_tenant_context(member, Organizations.legacy_organization_slug())

      assert {:ok, booking} = SubmitBooking.call(member_context, member, slot.id)
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

      counted =
        athlete_conn
        |> recycle()
        |> patch(
          "/api/executions/#{execution["id"]}/progress",
          valid
          |> Map.merge(%{
            expected_version: updated["lock_version"],
            operation_id: Ecto.UUID.generate(),
            kpi_counters: %{pauses: 2, skips: 1, bogus: 7}
          })
        )
        |> json_response(200)
        |> Map.fetch!("execution")

      assert %{"pauses" => 2, "skips" => 1, "position" => %{"format" => "for_time"}} =
               counted["kpi_counters"]

      refute Map.has_key?(counted["kpi_counters"], "bogus")

      stale_counters =
        athlete_conn
        |> recycle()
        |> patch(
          "/api/executions/#{execution["id"]}/progress",
          valid
          |> Map.merge(%{
            expected_version: counted["lock_version"],
            operation_id: Ecto.UUID.generate(),
            kpi_counters: %{pauses: 1}
          })
        )
        |> json_response(200)
        |> Map.fetch!("execution")

      assert stale_counters["kpi_counters"]["pauses"] == 2
      assert stale_counters["duration_adjustments"] == %{}
      updated = stale_counters

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

    test "progress stores clock adjustments for timed segments with authored context", %{
      conn: conn
    } do
      admin = create_admin!("execution_adjust_admin")
      athlete_conn = authenticate_as_member(conn, "execution_adjust_athlete")
      :ok = ensure_scale_level!(legacy_context!(admin), "scaled", "Scaled")

      {:ok, workout} =
        Workouts.create_workout(legacy_context!(admin), admin, %{
          title: "Adjustable AMRAP",
          type: "crossfit",
          sections: [
            %{
              name: "AMRAP 10",
              order: 1,
              scoreable: false,
              timer_config: %{type: "amrap", duration_seconds: 600},
              exercises: [%{name: "Burpee", order: 1, prescription_value: 10}]
            }
          ]
        })

      execution =
        athlete_conn
        |> post("/api/executions", %{master_workout_id: workout.id, source: "self_selected"})
        |> json_response(201)
        |> Map.fetch!("execution")

      updated =
        athlete_conn
        |> recycle()
        |> patch("/api/executions/#{execution["id"]}/progress", %{
          expected_version: execution["lock_version"],
          operation_id: Ecto.UUID.generate(),
          checked_exercise_ids: [],
          current_segment_index: 0,
          status: "paused",
          paused_elapsed_ms: 1_000,
          total_elapsed_ms: 1_000,
          section_elapsed_ms: %{},
          segment_cycle_counts: %{},
          duration_adjustments: %{"segment:0" => 120, "segment:7" => 30}
        })
        |> json_response(200)
        |> Map.fetch!("execution")

      assert %{
               "segment:0" => %{
                 "delta_seconds" => 120,
                 "authored_seconds" => 600,
                 "section_name" => "AMRAP 10"
               }
             } = updated["duration_adjustments"]

      refute Map.has_key?(updated["duration_adjustments"], "segment:7")
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

    test "comments on an execution are one list, upserted by id and by change, without notifying staff",
         %{conn: conn} do
      admin = create_admin!("execution_comment_admin")
      athlete_conn = authenticate_as_member(conn, "execution_comment_athlete")
      workout = workout_with_scale!(admin)
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

      note_id = Ecto.UUID.generate()

      comment =
        athlete_conn
        |> recycle()
        |> json_put("/api/journal/comments/#{note_id}", %{
          entry_kind: "execution",
          entry_id: execution_id,
          exercise_id: exercise_id,
          selected_text: "Thruster",
          selection_start: 0,
          selection_end: 8,
          tags: ["form"],
          body: "Needed more rest"
        })
        |> json_response(200)
        |> Map.fetch!("comment")

      assert %{"id" => ^note_id, "body" => "Needed more rest", "tags" => ["form"]} = comment

      change = %{
        patch_id: "segment:0:#{exercise_id}:1:reps",
        section_id: section_id,
        exercise_id: exercise_id,
        set_index: 1,
        field: "reps",
        canonical_value: 10,
        actual_value: 8,
        note: "Grip gave out"
      }

      [first_change] =
        athlete_conn
        |> recycle()
        |> json_post("/api/journal/comments/batch", %{
          comments: [
            %{
              id: Ecto.UUID.generate(),
              entry_kind: "execution",
              entry_id: execution_id,
              change: change
            }
          ]
        })
        |> json_response(200)
        |> Map.fetch!("comments")

      assert first_change["body"] == "Grip gave out"
      assert first_change["change"]["type"] == "reps_changed"
      refute Map.has_key?(first_change["change"], "note")

      # The same change from another surface updates the same comment.
      [second_change] =
        athlete_conn
        |> recycle()
        |> json_post("/api/journal/comments/batch", %{
          comments: [
            %{
              id: Ecto.UUID.generate(),
              entry_kind: "execution",
              entry_id: execution_id,
              change: %{change | actual_value: 7}
            }
          ]
        })
        |> json_response(200)
        |> Map.fetch!("comments")

      assert second_change["id"] == first_change["id"]
      assert second_change["change"]["actual_value"] == 7

      comments =
        athlete_conn
        |> recycle()
        |> get("/api/executions/#{execution_id}")
        |> json_response(200)
        |> get_in(["execution", "comments"])

      assert Enum.map(comments, & &1["id"]) == [note_id, first_change["id"]]

      athlete_conn
      |> recycle()
      |> delete("/api/journal/comments/#{note_id}")
      |> response(204)

      assert [%{"id" => remaining}] =
               athlete_conn
               |> recycle()
               |> get("/api/executions/#{execution_id}")
               |> json_response(200)
               |> get_in(["execution", "comments"])

      assert remaining == first_change["id"]
      assert Notifications.list_for_user(admin.id) == []
    end

    test "comments are only written by the entry's owner and validate their change", %{conn: conn} do
      admin = create_admin!("comment_validation_admin")
      athlete_conn = authenticate_as_member(conn, "comment_validation_member")
      other_conn = authenticate_as_member(build_conn(), "comment_validation_other")
      workout = workout_with_scale!(admin)

      execution_id =
        athlete_conn
        |> post("/api/executions", %{
          master_workout_id: workout.id,
          scale_level_slug: "scaled",
          source: "self_selected"
        })
        |> json_response(201)
        |> get_in(["execution", "id"])

      other_conn
      |> json_put("/api/journal/comments/#{Ecto.UUID.generate()}", %{
        entry_kind: "execution",
        entry_id: execution_id,
        body: "Not mine"
      })
      |> json_response(404)

      athlete_conn
      |> recycle()
      |> json_put("/api/journal/comments/#{Ecto.UUID.generate()}", %{
        entry_kind: "execution",
        entry_id: execution_id,
        change: %{
          patch_id: "x",
          section_id: "s",
          field: "reps",
          canonical_value: 5,
          actual_value: 5
        }
      })
      |> json_response(400)

      athlete_conn
      |> recycle()
      |> json_put("/api/journal/comments/#{Ecto.UUID.generate()}", %{
        entry_kind: "execution",
        entry_id: execution_id,
        body: "   "
      })
      |> json_response(422)
    end
  end

  describe "workout vault and repeats (ADR-098)" do
    test "a client repeats a completed workout as a new dated entry and sees it in the vault",
         %{conn: conn} do
      admin = create_admin!("vault_admin")
      member = create_user!(:member, "vault_member")
      other_conn = authenticate_as_member(conn, "vault_other")
      workout = workout_with_scale!(admin)
      member_conn = put_bearer_token(conn, member)

      start = fn source, reference ->
        member_conn
        |> recycle()
        |> post("/api/executions", %{
          master_workout_id: workout.id,
          scale_level_slug: "scaled",
          source: source,
          source_reference_id: reference
        })
      end

      first = start.("self_selected", nil) |> json_response(201) |> Map.fetch!("execution")

      # Only completed executions can be done again.
      assert start.("repeat", first["id"]) |> json_response(403)

      member_conn
      |> recycle()
      |> patch("/api/executions/#{first["id"]}/complete", %{section_scores: []})
      |> json_response(200)

      again = start.("repeat", first["id"]) |> json_response(201) |> Map.fetch!("execution")
      assert again["source"] == "repeat"
      assert again["source_reference_id"] == first["id"]
      refute again["id"] == first["id"]

      # Someone else's history is not a source.
      assert other_conn
             |> post("/api/executions", %{
               master_workout_id: workout.id,
               scale_level_slug: "scaled",
               source: "repeat",
               source_reference_id: first["id"]
             })
             |> json_response(403)

      member_conn
      |> recycle()
      |> patch("/api/executions/#{again["id"]}/complete", %{section_scores: []})
      |> json_response(200)

      [entry] =
        member_conn
        |> recycle()
        |> get("/api/executions/vault")
        |> json_response(200)
        |> Map.fetch!("workouts")

      assert entry["master_workout_id"] == workout.id
      assert entry["workout_title"] == "Execution Workout"
      assert entry["completed_count"] == 2

      assert Enum.map(entry["entries"], & &1["id"]) |> Enum.sort() ==
               Enum.sort([first["id"], again["id"]])
    end
  end

  defp workout_with_scale!(admin) do
    :ok = ensure_scale_level!(legacy_context!(admin), "scaled", "Scaled")

    {:ok, workout} =
      Workouts.create_workout(legacy_context!(admin), admin, %{
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
    :ok = ensure_scale_level!(legacy_context!(admin), "scaled", "Scaled")

    {:ok, workout} =
      Workouts.create_workout(legacy_context!(admin), admin, %{
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

  defp ensure_scale_level!(context, slug, label) do
    levels = Workouts.list_scale_levels(context)

    if Enum.any?(levels, &(&1.slug == slug)) do
      :ok
    else
      new_level = %{slug: slug, label: label, sort_order: length(levels) + 1}

      {:ok, _levels} =
        Workouts.replace_scale_levels(
          context,
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
      Identity.register(%{
        nickname: nickname,
        password: "S3cur3P@ss!42",
        role: role,
        email: "u#{System.unique_integer([:positive])}@placeholder.invalid"
      })

    # Executing a gym's workout requires belonging to that gym (F-03). These
    # users previously had no membership at all and only passed because the
    # source check looked at the account-wide role.
    {:ok, _membership} = Palee.Organizations.ensure_legacy_membership_for_migration(user)

    user
  end

  defp legacy_context!(admin) do
    {:ok, context} =
      Organizations.resolve_tenant_context(admin, Organizations.legacy_organization_slug())

    context
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
    {:ok, _membership} = Organizations.ensure_legacy_membership_for_migration(admin, :owner)
    admin
  end

  defp json_put(conn, path, body), do: json_request(conn, :put, path, body)
  defp json_post(conn, path, body), do: json_request(conn, :post, path, body)

  defp json_request(conn, method, path, body) do
    conn
    |> put_req_header("content-type", "application/json")
    |> dispatch(@endpoint, method, path, Jason.encode!(body))
  end
end
