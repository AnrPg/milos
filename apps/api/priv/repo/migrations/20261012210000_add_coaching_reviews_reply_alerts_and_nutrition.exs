defmodule MilosTraining.Repo.Migrations.AddCoachingReviewsReplyAlertsAndNutrition do
  use Ecto.Migration

  # ADR-098: form reviews, overdue coach replies and nutrition plans.

  @phase_b_types [
    "booking_approved",
    "booking_rejected",
    "booking_pending",
    "booking_timeout",
    "workout_note",
    "workout_changed",
    "workout_deleted",
    "workout_rejected",
    "workout_moved",
    "workout_assigned",
    "workout_assignment_requested",
    "review_submitted",
    "athlete_message",
    "workout_completed",
    "admin_note",
    "challenge_completed",
    "chat_message",
    "invoice_issued",
    "payment_reminder",
    "booking_waitlist_promoted",
    "package_expiring"
  ]

  @types @phase_b_types ++
           [
             "form_review_submitted",
             "form_review_completed",
             "coaching_reply_overdue",
             "nutrition_plan_updated"
           ]

  @class_type_key "allowance_key ~ '^class_visits:[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'"
  @phase_b_keys "'class_visits', 'coaching_touchpoints', 'event_visits', 'guest_passes', 'open_gym_visits'"

  def up do
    replace_allowance_keys(
      @phase_b_keys <> ", 'pt_sessions', 'assessments', 'form_reviews'",
      true
    )

    create table(:coaching_form_reviews, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :video_url, :text, null: false
      add :note, :text
      add :exercise_name, :string
      add :execution_id, :binary_id
      add :status, :string, null: false, default: "submitted"
      add :reservation_id, :binary_id
      add :reviewer_id, :binary_id
      add :feedback, :text
      add :reviewed_at, :utc_datetime_usec
      timestamps(type: :utc_datetime_usec)
    end

    create constraint(:coaching_form_reviews, :coaching_form_reviews_status,
             check: "status IN ('submitted', 'reviewed', 'withdrawn')"
           )

    create index(:coaching_form_reviews, [:organization_id, :status, :inserted_at])
    create index(:coaching_form_reviews, [:user_id, :inserted_at])
    enable_tenant_rls("coaching_form_reviews")

    create table(:coaching_reply_alerts, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :message_id, :binary_id, null: false
      add :thread_id, :binary_id, null: false
      add :notified_at, :utc_datetime_usec, null: false
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:coaching_reply_alerts, [:organization_id, :message_id])
    enable_tenant_rls("coaching_reply_alerts")

    create table(:nutrition_plans, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :title, :string, null: false
      add :body, :text, null: false
      add :daily_calories, :integer
      add :protein_grams, :integer
      add :carbs_grams, :integer
      add :fat_grams, :integer
      add :updated_by_id, :binary_id
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:nutrition_plans, [:organization_id, :user_id])
    enable_tenant_rls("nutrition_plans")

    replace_notification_types(@types)
  end

  def down do
    execute(
      "DELETE FROM notifications WHERE type IN ('form_review_submitted', 'form_review_completed', 'coaching_reply_overdue', 'nutrition_plan_updated')"
    )

    replace_notification_types(@phase_b_types)
    # The ledger is append-only: Phase C entries stay; new rows use the old list.
    replace_allowance_keys(@phase_b_keys, false)
    drop table(:nutrition_plans)
    drop table(:coaching_reply_alerts)
    drop table(:coaching_form_reviews)
  end

  defp replace_notification_types(types) do
    drop constraint(:notifications, :notifications_type_check)

    create constraint(:notifications, :notifications_type_check,
             check: "type IN (#{Enum.map_join(types, ", ", &"'#{&1}'")})"
           )
  end

  defp replace_allowance_keys(keys, validate?) do
    drop constraint(:finance_entitlement_usage_entries, :entitlement_usage_allowance_key)

    create constraint(:finance_entitlement_usage_entries, :entitlement_usage_allowance_key,
             check: "allowance_key IN (#{keys}) OR #{@class_type_key}",
             validate: validate?
           )
  end

  defp enable_tenant_rls(table) do
    execute("""
    CREATE TRIGGER #{table}_apply_tenant_context
    BEFORE INSERT OR UPDATE ON #{table}
    FOR EACH ROW EXECUTE FUNCTION milos_apply_tenant_context()
    """)

    execute("""
    CREATE POLICY #{table}_tenant_policy ON #{table}
    USING (organization_id = NULLIF(current_setting('app.organization_id', true), '')::uuid)
    WITH CHECK (organization_id = NULLIF(current_setting('app.organization_id', true), '')::uuid)
    """)

    execute("ALTER TABLE #{table} ENABLE ROW LEVEL SECURITY")
    execute("ALTER TABLE #{table} FORCE ROW LEVEL SECURITY")
  end
end
