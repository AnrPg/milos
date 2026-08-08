defmodule MilosTraining.Repo.Migrations.DropLegacyOrganizationDefaults do
  use Ecto.Migration

  @tenant_tables ~w(
    class_types
    scheduling_settings
    class_series
    scheduled_classes
    bookings
    class_attendance_records
    master_workouts
    workout_folders
    workout_sections
    workout_exercises
    exercise_variations
    assigned_workouts
    assigned_workout_athletes
    membership_packages
    memberships
    membership_package_subscriptions
    membership_payments
    promotion_campaigns
    promotion_codes
    promotion_redemptions
    referral_programs
    referral_events
    referral_rewards
    finance_invoices
    finance_invoice_lines
    finance_payment_reversals
    finance_credit_ledger_entries
    finance_entitlement_usage_entries
    finance_settings
    messaging_threads
    messaging_participants
    messaging_messages
    seasonal_challenges
    user_challenge_progress
    challenge_leaderboard_opt_ins
    leaderboard_opt_ins
    gamification_settings
    attendance_records
    communication_threads
    communication_messages
    analytics_events
    notification_click_events
    push_dispatch_attempts
    review_questionnaires
    reviews
    review_answers
  )

  def up do
    Enum.each(@tenant_tables, fn table ->
      execute("ALTER TABLE #{table} ALTER COLUMN organization_id DROP DEFAULT")
    end)
  end

  def down do
    Enum.each(@tenant_tables, fn table ->
      execute(
        "ALTER TABLE #{table} ALTER COLUMN organization_id SET DEFAULT milos_legacy_organization_id()"
      )
    end)
  end
end
