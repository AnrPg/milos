defmodule MilosTraining.Execution.Domain.TrainingLogPolicyTest do
  use ExUnit.Case, async: true

  alias MilosTraining.Execution.Domain.TrainingLogPolicy

  @now ~U[2026-10-12 12:00:00.000000Z]

  describe "normalize_details/3" do
    test "normalizes a freeform entry with performed exercises" do
      assert {:ok, details} =
               TrainingLogPolicy.normalize_details(
                 %{
                   "title" => "  Hotel gym  ",
                   "performed_at" => "2026-10-11T07:30:00Z",
                   "timezone" => "Europe/Athens",
                   "duration_seconds" => 2700,
                   "perceived_effort" => 7,
                   "notes" => "  felt strong ",
                   "performed_exercises" => [
                     %{
                       "name" => "Back squat",
                       "exercise_ref" => "back-squat",
                       "sets" => 5,
                       "reps" => 5,
                       "load" => 100,
                       "load_unit" => "kg"
                     },
                     %{"name" => "Run", "distance" => 5, "distance_unit" => "km"}
                   ]
                 },
                 now: @now,
                 freeform?: true
               )

      assert details.title == "Hotel gym"
      assert details.performed_at_utc == ~U[2026-10-11 07:30:00Z]
      assert details.performed_at_tz == "Europe/Athens"
      assert details.duration_seconds == 2700
      assert details.perceived_effort == 7
      assert details.notes == "felt strong"
      assert details.section_scores == []
      assert details.exercise_modifications == []

      assert [
               %{
                 "row_index" => 1,
                 "name" => "Back squat",
                 "exercise_ref" => "back-squat",
                 "load_unit" => "kg"
               },
               %{"row_index" => 2, "name" => "Run", "distance_unit" => "km"} = run
             ] = details.performed_exercises

      refute Map.has_key?(run, "load")
    end

    test "requires a title for freeform entries and a performed time on create" do
      assert {:error, [title: "can't be blank"]} =
               TrainingLogPolicy.normalize_details(%{"performed_at" => "2026-10-11T07:30:00Z"},
                 now: @now,
                 freeform?: true
               )

      assert {:error, [performed_at_utc: "can't be blank"]} =
               TrainingLogPolicy.normalize_details(%{}, now: @now)
    end

    test "rejects performances in the future or older than a year" do
      assert {:error, [performed_at_utc: "cannot be in the future"]} =
               TrainingLogPolicy.normalize_details(%{"performed_at" => "2026-10-12T14:00:00Z"},
                 now: @now
               )

      assert {:error, [performed_at_utc: "is too far in the past"]} =
               TrainingLogPolicy.normalize_details(%{"performed_at" => "2025-09-01T00:00:00Z"},
                 now: @now
               )

      assert {:ok, _details} =
               TrainingLogPolicy.normalize_details(%{"performed_at" => "2026-10-12T12:10:00Z"},
                 now: @now
               )
    end

    test "validates effort and duration bounds" do
      base = %{"performed_at" => "2026-10-11T07:30:00Z"}

      assert {:error, [perceived_effort: _]} =
               TrainingLogPolicy.normalize_details(Map.put(base, "perceived_effort", 11),
                 now: @now
               )

      assert {:error, [duration_seconds: _]} =
               TrainingLogPolicy.normalize_details(Map.put(base, "duration_seconds", -1),
                 now: @now
               )
    end

    test "accepts section scores only for scoreable sections of the source workout" do
      params = %{
        "performed_at" => "2026-10-11T07:30:00Z",
        "section_scores" => [%{"section_id" => "s1", "value" => 120, "unit" => "seconds"}]
      }

      assert {:ok, %{section_scores: [%{"section_id" => "s1", "value" => 120}]}} =
               TrainingLogPolicy.normalize_details(params,
                 now: @now,
                 structured?: true,
                 allowed_section_ids: ["s1"]
               )

      assert {:error, [section_scores: _]} =
               TrainingLogPolicy.normalize_details(params, now: @now, allowed_section_ids: [])
    end

    test "reuses ADR-050 modification patches for structured sources only" do
      patch = %{
        "patch_id" => "segment:0:squat:1:reps",
        "section_id" => "s1",
        "exercise_id" => "squat",
        "set_index" => 1,
        "field" => "reps",
        "canonical_value" => 10,
        "actual_value" => 8
      }

      params = %{"performed_at" => "2026-10-11T07:30:00Z", "exercise_modifications" => [patch]}

      assert {:ok, %{exercise_modifications: [%{"type" => "reps_changed"}]}} =
               TrainingLogPolicy.normalize_details(params, now: @now, structured?: true)

      assert {:error, [exercise_modifications: "require a workout source"]} =
               TrainingLogPolicy.normalize_details(params, now: @now, structured?: false)
    end

    test "update mode only returns the keys that were sent" do
      assert {:ok, %{notes: "updated"} = changes} =
               TrainingLogPolicy.normalize_details(%{"notes" => "updated"}, [now: @now], :update)

      assert map_size(changes) == 1
    end

    test "rejects malformed performed exercises" do
      assert {:error, [performed_exercises: _]} =
               TrainingLogPolicy.normalize_details(
                 %{
                   "performed_at" => "2026-10-11T07:30:00Z",
                   "performed_exercises" => [%{"name" => "Squat", "load_unit" => "stone"}]
                 },
                 now: @now
               )
    end
  end

  describe "double_counted?/3" do
    @completed ~U[2026-10-11 08:00:00Z]

    test "class logs conflict with a completed execution of the same booking" do
      executions = [
        %{source: "class_booking", source_reference_id: "booking-1", completed_at_utc: @completed}
      ]

      assert TrainingLogPolicy.double_counted?(
               %{source_type: "class", booking_id: "booking-1"},
               executions,
               @completed
             )

      refute TrainingLogPolicy.double_counted?(
               %{source_type: "class", booking_id: "booking-2"},
               executions,
               @completed
             )
    end

    test "unfinished executions never count" do
      executions = [
        %{source: "assigned", source_reference_id: "assignment-1", completed_at_utc: nil}
      ]

      refute TrainingLogPolicy.double_counted?(
               %{source_type: "assigned_workout", source_reference_id: "assignment-1"},
               executions,
               @completed
             )
    end

    test "library workouts conflict only on the same calendar day" do
      executions = [
        %{source: "self_selected", master_workout_id: "w1", completed_at_utc: @completed}
      ]

      source = %{source_type: "library_workout", master_workout_id: "w1"}

      assert TrainingLogPolicy.double_counted?(source, executions, ~U[2026-10-11 18:00:00Z])
      refute TrainingLogPolicy.double_counted?(source, executions, ~U[2026-10-10 18:00:00Z])
    end

    test "freeform never conflicts" do
      refute TrainingLogPolicy.double_counted?(%{source_type: "freeform"}, [], @completed)
    end
  end

  describe "authorize_class/2" do
    @slot %{id: "slot-1", scheduled_at: ~U[2026-10-11 07:00:00Z]}

    test "approved booking after the class started qualifies" do
      assert {:ok, "booking-1"} =
               TrainingLogPolicy.authorize_class(
                 %{slot: @slot, booking: %{id: "booking-1", status: :approved}, attendance: nil},
                 @now
               )
    end

    test "attendance mark qualifies even without a booking" do
      assert {:ok, nil} =
               TrainingLogPolicy.authorize_class(
                 %{slot: @slot, booking: nil, attendance: %{status: "attended"}},
                 @now
               )
    end

    test "explicit non-attendance wins over an approved booking" do
      assert {:error, :training_log_source_forbidden} =
               TrainingLogPolicy.authorize_class(
                 %{
                   slot: @slot,
                   booking: %{id: "booking-1", status: :approved},
                   attendance: %{status: "no_show"}
                 },
                 @now
               )
    end

    test "future classes and unbooked classes are rejected" do
      future = %{@slot | scheduled_at: ~U[2026-10-13 07:00:00Z]}

      assert {:error, :training_log_source_not_started} =
               TrainingLogPolicy.authorize_class(
                 %{slot: future, booking: %{id: "b", status: :approved}, attendance: nil},
                 @now
               )

      assert {:error, :training_log_source_forbidden} =
               TrainingLogPolicy.authorize_class(
                 %{slot: @slot, booking: nil, attendance: nil},
                 @now
               )

      assert {:error, :not_found} = TrainingLogPolicy.authorize_class(%{slot: nil}, @now)
    end
  end

  describe "ensure_editable/2 and void_attrs/2" do
    test "only the owner may change a live entry" do
      assert :ok = TrainingLogPolicy.ensure_editable(%{user_id: "u1", status: "logged"}, "u1")

      assert {:error, :training_log_entry_voided} =
               TrainingLogPolicy.ensure_editable(%{user_id: "u1", status: "voided"}, "u1")

      assert {:error, :not_found} =
               TrainingLogPolicy.ensure_editable(%{user_id: "u1", status: "logged"}, "u2")
    end

    test "void attrs carry the trimmed reason and time" do
      assert {:ok, %{status: "voided", voided_at: @now, void_reason: "duplicate"}} =
               TrainingLogPolicy.void_attrs("  duplicate ", @now)

      assert {:ok, %{void_reason: nil}} = TrainingLogPolicy.void_attrs(nil, @now)
    end
  end

  describe "completion_record/1" do
    test "projects live entries into the execution-shaped completion record" do
      entry = %{
        id: "e1",
        user_id: "u1",
        organization_id: "o1",
        master_workout_id: "w1",
        scale_level_slug: nil,
        source_type: "class",
        source_reference_id: "slot-1",
        performed_at_utc: ~U[2026-10-11 07:00:00Z],
        performed_at_tz: "UTC",
        section_scores: [%{"section_id" => "s1", "value" => 10}],
        exercise_modifications: [],
        status: "logged"
      }

      record = TrainingLogPolicy.completion_record(entry)
      assert record.completed_at_utc == ~U[2026-10-11 07:00:00Z]
      assert record.completion_source == "training_log"
      assert record.section_scores == [%{"section_id" => "s1", "value" => 10}]

      assert TrainingLogPolicy.completion_records([entry, %{entry | status: "voided"}]) == [
               record
             ]
    end
  end

  describe "replay_decision/2 (ADR-120)" do
    test "replays when raw params or a server source name the same source" do
      entry = %{source_type: "class", source_reference_id: "slot-1"}

      assert :replay =
               TrainingLogPolicy.replay_decision(entry, %{
                 "source_type" => "class",
                 "source_reference_id" => "slot-1"
               })

      assert :replay =
               TrainingLogPolicy.replay_decision(entry, %{
                 source_type: :class,
                 source_reference_id: "slot-1"
               })
    end

    test "treats blank freeform references as equal" do
      entry = %{source_type: "freeform", source_reference_id: nil}

      assert :replay =
               TrainingLogPolicy.replay_decision(entry, %{
                 "source_type" => "freeform",
                 "source_reference_id" => ""
               })
    end

    test "conflicts when the key names a different source" do
      entry = %{source_type: "class", source_reference_id: "slot-1"}

      assert {:error, :idempotency_key_conflict} =
               TrainingLogPolicy.replay_decision(entry, %{
                 "source_type" => "class",
                 "source_reference_id" => "slot-2"
               })

      assert {:error, :idempotency_key_conflict} =
               TrainingLogPolicy.replay_decision(entry, %{"source_type" => "freeform"})
    end
  end
end
