defmodule MilosTraining.Repo.Migrations.RemoveRlsLegacyOrgCoalesceFallback do
  use Ecto.Migration

  @moduledoc """
  F-04: removes the `COALESCE(session_var, milos_legacy_organization_id())`
  fallback from every RLS policy that still has it, replacing it with a bare
  `organization_id = session_var` equality - matching the pattern Scheduling
  already uses correctly (bookings, class_types, class_series,
  scheduled_classes, class_attendance_records, scheduling_settings never had
  the fallback in their policies).

  This does NOT touch the `DEFAULT milos_legacy_organization_id()` column
  defaults on the same tables - those are a write-path convenience for code
  that inserts without an active tenant session (see F-24/F-25/F-26) and are
  deliberately left alone until that write-path work lands, per the
  remediation roadmap's own sequencing note (P1.1 depends-on ordering).
  Removing the column defaults now, before those jobs carry explicit
  organization_id, would turn silent misattribution into hard NOT NULL
  failures for those jobs.
  """

  @tables ~w(
    analytics_events assigned_workout_athletes assigned_workouts attendance_records
    challenge_leaderboard_opt_ins communication_messages communication_threads
    exercise_variations finance_credit_ledger_entries finance_entitlement_usage_entries
    finance_invoice_lines finance_invoices finance_payment_reversals finance_settings
    gamification_settings leaderboard_opt_ins master_workouts
    membership_package_subscriptions membership_packages membership_payments
    memberships messaging_messages messaging_participants messaging_threads
    notification_click_events promotion_campaigns promotion_codes
    promotion_redemptions push_dispatch_attempts referral_events referral_programs
    referral_rewards review_answers review_questionnaires reviews
    seasonal_challenges user_challenge_progress workout_exercises workout_folders
    workout_sections
  )

  def up do
    for table <- @tables do
      execute("DROP POLICY IF EXISTS #{table}_tenant_policy ON #{table}")

      execute("""
      CREATE POLICY #{table}_tenant_policy ON #{table}
      USING (organization_id = NULLIF(current_setting('app.organization_id', true), '')::uuid)
      WITH CHECK (organization_id = NULLIF(current_setting('app.organization_id', true), '')::uuid)
      """)
    end
  end

  def down do
    for table <- @tables do
      execute("DROP POLICY IF EXISTS #{table}_tenant_policy ON #{table}")

      execute("""
      CREATE POLICY #{table}_tenant_policy ON #{table}
      USING (
        organization_id = COALESCE(
          NULLIF(current_setting('app.organization_id', true), '')::uuid,
          milos_legacy_organization_id()
        )
      )
      WITH CHECK (
        organization_id = COALESCE(
          NULLIF(current_setting('app.organization_id', true), '')::uuid,
          milos_legacy_organization_id()
        )
      )
      """)
    end
  end
end
