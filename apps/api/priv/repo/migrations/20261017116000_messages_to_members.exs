defmodule Palee.Repo.Migrations.MessagesToMembers do
  @moduledoc """
  ADR-140 §6-7 (M5.6): three kinds of message to a member.

  * `coaching_note` becomes `coaching_message`; `box_message` is new, with an
    optional `topic` (booking, payment, membership, facility).
  * The `admin_note` notification becomes `coaching_message`, and
    `box_message` notifies a member of a message from the box.
  * `coaching_aggregates` counts coaching messages and the reply requests
    still waiting for an answer (vision §7.7 Ζητάω απάντηση).
  """

  use Ecto.Migration

  @notification_types ~w(
    booking_approved booking_rejected booking_pending booking_timeout workout_note
    workout_changed workout_deleted workout_rejected workout_moved workout_assigned
    workout_assignment_requested review_submitted athlete_message workout_completed
    coaching_message box_message challenge_completed chat_message invoice_issued
    payment_reminder booking_waitlist_promoted package_expiring form_review_submitted
    form_review_completed coaching_reply_overdue nutrition_plan_updated
    appointment_booked appointment_cancelled coach_client_assigned coach_note_viewed
    inventory_repair_needed inventory_stock_low inventory_digest subscription_expiring
    subscription_grace access_ended
  )

  def up do
    execute(
      "UPDATE messaging_messages SET message_type = 'coaching_message' WHERE message_type = 'coaching_note'"
    )

    alter table(:messaging_messages) do
      add :topic, :string
    end

    create constraint(:messaging_messages, :messaging_messages_type_check,
             check: "message_type IN ('chat', 'coaching_message', 'box_message', 'system')"
           )

    create constraint(:messaging_messages, :messaging_messages_topic_check,
             check:
               "topic IS NULL OR (message_type = 'box_message' AND " <>
                 "topic IN ('booking', 'payment', 'membership', 'facility'))"
           )

    drop constraint(:notifications, :notifications_type_check)
    execute("UPDATE notifications SET type = 'coaching_message' WHERE type = 'admin_note'")

    create constraint(:notifications, :notifications_type_check,
             check: "type IN (#{Enum.map_join(@notification_types, ", ", &"'#{&1}'")})"
           )

    recreate_coaching_aggregates()
  end

  def down do
    raise Ecto.MigrationError, message: "message kinds cannot be folded back into coaching notes"
  end

  defp recreate_coaching_aggregates do
    execute("DROP MATERIALIZED VIEW IF EXISTS coaching_aggregates")

    execute("""
    CREATE MATERIALIZED VIEW coaching_aggregates AS
    SELECT
      membership.organization_id,
      date_trunc('week', timezone('utc', NOW()))::date AS period_start,
      COUNT(DISTINCT membership.user_id) FILTER (
        WHERE EXISTS (
          SELECT 1
          FROM workout_executions recent_execution
          WHERE recent_execution.user_id = membership.user_id
            AND recent_execution.organization_id = membership.organization_id
            AND recent_execution.completed_at_utc >= timezone('utc', NOW()) - INTERVAL '14 days'
        )
      )::integer AS active_athlete_count,
      COUNT(DISTINCT membership.user_id) FILTER (
        WHERE NOT EXISTS (
          SELECT 1
          FROM workout_executions recent_execution
          WHERE recent_execution.user_id = membership.user_id
            AND recent_execution.organization_id = membership.organization_id
            AND recent_execution.completed_at_utc >= timezone('utc', NOW()) - INTERVAL '14 days'
        )
      )::integer AS inactive_athlete_count,
      COUNT(DISTINCT execution.id) FILTER (
        WHERE execution.completed_at_utc >= date_trunc('week', timezone('utc', NOW()))
      )::integer AS completed_workouts_this_week,
      (
        SELECT COUNT(*)
        FROM messaging_messages message
        WHERE message.organization_id = membership.organization_id
          AND message.message_type = 'coaching_message'
          AND message.inserted_at >= date_trunc('week', timezone('utc', NOW()))
      )::integer AS coaching_messages_this_week,
      COALESCE(
        COUNT(DISTINCT execution.id) FILTER (
          WHERE execution.completed_at_utc >= date_trunc('week', timezone('utc', NOW()))
        )::float / NULLIF(COUNT(DISTINCT membership.user_id), 0)::float,
        0.0
      ) AS average_completion_rate,
      (
        SELECT COUNT(*)
        FROM messaging_messages request
        WHERE request.organization_id = membership.organization_id
          AND request.subject_id IS NOT NULL
          AND NOT EXISTS (
            SELECT 1
            FROM messaging_messages answer
            WHERE answer.thread_id = request.thread_id
              AND answer.sender_id <> request.sender_id
              AND answer.sequence_number > request.sequence_number
          )
      )::integer AS awaiting_reply_count
    FROM organization_memberships membership
    JOIN organizations organization ON organization.id = membership.organization_id
    LEFT JOIN workout_executions execution
      ON execution.user_id = membership.user_id
      AND execution.organization_id = membership.organization_id
    WHERE membership.status = 'active'
      AND membership.role = 'athlete'
      AND organization.status = 'active'
    GROUP BY membership.organization_id
    """)

    execute(
      "CREATE UNIQUE INDEX coaching_aggregates_organization_period_index " <>
        "ON coaching_aggregates (organization_id, period_start)"
    )
  end
end
