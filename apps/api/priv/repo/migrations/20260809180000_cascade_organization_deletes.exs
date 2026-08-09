defmodule MilosTraining.Repo.Migrations.CascadeOrganizationDeletes do
  use Ecto.Migration

  # "Permanently delete organization" (platform_organization_controller#delete)
  # only ever succeeded for an organization with zero rows anywhere: every
  # tenant-data table's organization_id FK was ON DELETE RESTRICT, so Postgres
  # rejected the delete the moment the org had a single workout, invoice,
  # membership, message, etc. That made the feature unusable for any org that
  # had actually been used - which is the only kind of org a vendor would ever
  # want to remove entirely, since an empty org can just as easily be left
  # alone. Switching these to CASCADE makes the button do what it already
  # claims to do ("This removes the organization immediately").
  #
  # Left alone: organizations.id itself (not a child here), and the four
  # tables already on CASCADE (organization_domains, organization_memberships,
  # organization_settings, registration_invitations).
  @tables ~w(
    analytics_events
    assigned_workout_athletes
    assigned_workouts
    attendance_records
    bookings
    challenge_leaderboard_opt_ins
    class_attendance_records
    class_series
    class_types
    communication_messages
    communication_threads
    exercise_variations
    finance_credit_ledger_entries
    finance_entitlement_usage_entries
    finance_invoice_lines
    finance_invoices
    finance_payment_reversals
    finance_settings
    gamification_settings
    injury_reports
    leaderboard_opt_ins
    master_workouts
    membership_package_subscriptions
    membership_packages
    membership_payments
    memberships
    messaging_messages
    messaging_participants
    messaging_threads
    notification_click_events
    notifications
    organization_provisioning_events
    promotion_campaigns
    promotion_codes
    promotion_redemptions
    push_dispatch_attempts
    referral_events
    referral_programs
    referral_rewards
    review_answers
    review_questionnaires
    reviews
    scheduled_classes
    scheduling_settings
    seasonal_challenges
    user_challenge_progress
    user_pr_history
    user_pr_records
    workout_executions
    workout_exercises
    workout_folders
    workout_sections
  )

  def up do
    for table <- @tables do
      execute("""
      ALTER TABLE #{table}
        DROP CONSTRAINT #{table}_organization_id_fkey,
        ADD CONSTRAINT #{table}_organization_id_fkey
          FOREIGN KEY (organization_id) REFERENCES organizations(id)
          ON DELETE CASCADE
      """)
    end
  end

  def down do
    for table <- @tables do
      execute("""
      ALTER TABLE #{table}
        DROP CONSTRAINT #{table}_organization_id_fkey,
        ADD CONSTRAINT #{table}_organization_id_fkey
          FOREIGN KEY (organization_id) REFERENCES organizations(id)
          ON DELETE RESTRICT
      """)
    end
  end
end
