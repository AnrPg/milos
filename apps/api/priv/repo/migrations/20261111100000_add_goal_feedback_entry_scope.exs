defmodule Palee.Repo.Migrations.AddGoalFeedbackEntryScope do
  @moduledoc """
  ADR-163 coach totals: which workout and which scheduled class a journal
  entry belongs to, and whether it was voided, so the goal-feedback summary
  can count the feedback rows a coach may read (the `goal_feedback` coach
  read policies decide which) per workout or per class.

  A training-log entry belongs to a class when it was logged from one
  (`source_type = 'class'`, the slot in `source_reference_id`); an execution
  when it was started from a class booking (`source = 'class_booking'`, the
  booking in `source_reference_id`).

  SECURITY DEFINER for the same reason as `palee_goal_feedback_entry`:
  executions, logs and bookings sit under other scopes than the coach's
  session. It answers about one entry and adds no table, so no new policy.
  The body names its arguments `$1`/`$2`: `bookings` has a `kind` column,
  which would shadow the `kind` argument.
  """

  use Ecto.Migration

  def up do
    execute("""
    CREATE OR REPLACE FUNCTION palee_goal_feedback_entry_scope(kind text, entry uuid)
    RETURNS TABLE (master_workout_id uuid, scheduled_class_id uuid, voided boolean)
    LANGUAGE sql
    STABLE
    SECURITY DEFINER
    SET search_path = public, pg_temp
    AS $$
      SELECT e.master_workout_id, b.scheduled_class_id, false
      FROM workout_executions e
      LEFT JOIN bookings b
        ON e.source = 'class_booking' AND b.id = e.source_reference_id
      WHERE $1 = 'execution' AND e.id = $2
      UNION ALL
      SELECT l.master_workout_id,
             CASE WHEN l.source_type = 'class' THEN l.source_reference_id END,
             l.voided_at IS NOT NULL
      FROM training_log_entries l
      WHERE $1 = 'training_log' AND l.id = $2
    $$
    """)
  end

  def down do
    execute("DROP FUNCTION IF EXISTS palee_goal_feedback_entry_scope(text, uuid)")
  end
end
