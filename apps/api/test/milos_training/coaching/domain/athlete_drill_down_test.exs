defmodule MilosTraining.Coaching.Domain.AthleteDrillDownTest do
  use ExUnit.Case, async: true

  alias MilosTraining.Coaching.Domain.AthleteDrillDown

  @today ~D[2026-06-13]

  test "builds an active athlete profile from assignments, completions, scores, and notes" do
    athlete = %{id: "athlete-1", nickname: "eleni", role: :athlete}

    assignments = [
      %{
        id: "assignment-1",
        master_workout_id: "workout-1",
        scheduled_for: "2026-06-12",
        admin_notes: "Keep volume controlled",
        execution_status: "completed",
        workout: %{id: "workout-1", title: "Strength A", type: "strength"}
      },
      %{
        id: "assignment-2",
        master_workout_id: "workout-2",
        scheduled_for: "2026-06-18",
        admin_notes: nil,
        workout: %{id: "workout-2", title: "Engine B", type: "aerobics"}
      }
    ]

    executions = [
      %{
        id: "execution-1",
        master_workout_id: "workout-1",
        workout_title: "Strength A",
        workout_type: "strength",
        status: "completed",
        source: "assigned",
        completed_at_utc: ~U[2026-06-12 10:00:00Z],
        started_at_utc: ~U[2026-06-12 09:30:00Z],
        section_scores: [
          %{section_id: "section-1", section_name: "Back squat", value: 120, unit: "kg"}
        ],
        exercise_notes: [
          %{
            "id" => "note-1",
            "note_text" => "Left knee felt tight",
            "inserted_at" => "2026-06-12T10:01:00Z"
          }
        ]
      }
    ]

    notes = [
      %{
        id: "coach-note-1",
        admin_id: "admin-1",
        athlete_id: "athlete-1",
        body: "Prioritize recovery this week.",
        inserted_at: ~U[2026-06-12 12:00:00Z]
      }
    ]

    drill_down = AthleteDrillDown.build(athlete, assignments, executions, notes, @today)

    assert drill_down.identity == %{
             user_id: "athlete-1",
             nickname: "eleni",
             role: "athlete"
           }

    assert drill_down.recent_activity.state == "active"
    assert drill_down.recent_activity.completed_workouts_last_14_days == 1
    assert drill_down.recent_activity.last_completed_at == ~U[2026-06-12 10:00:00Z]

    assert Enum.map(drill_down.assigned_workouts, & &1.status) == ["completed", "upcoming"]
    assert [%{workout_type: "strength", entries: [%{value: 120}]}] = drill_down.score_trends
    assert [%{type: "admin_note"}, %{type: "athlete_execution_note"}] = drill_down.notes_context
    assert drill_down.attention_cues == []

    actions = Map.new(drill_down.actions, &{&1.key, &1})
    assert actions["write_note"].available
    assert actions["review_history"].available
  end

  test "marks athletes with overdue assignments and no completions as needing follow-up" do
    drill_down =
      AthleteDrillDown.build(
        %{id: "athlete-2", nickname: "petros", role: :athlete},
        [
          %{
            id: "assignment-3",
            scheduled_for: "2026-06-01",
            workout: %{title: "Missed day", type: "crossfit"}
          }
        ],
        [],
        [],
        @today
      )

    assert drill_down.recent_activity.state == "inactive"
    assert [%{type: "overdue_assignment", severity: "high"} | _] = drill_down.attention_cues

    actions = Map.new(drill_down.actions, &{&1.key, &1})
    assert actions["write_note"].available
  end
end
