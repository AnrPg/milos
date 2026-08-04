defmodule MilosTraining.Infrastructure.Tenancy.Audit do
  alias MilosTraining.Repo

  @ready_tenant_tables ~w(
    class_types scheduling_settings class_series scheduled_classes bookings
    class_attendance_records
    master_workouts workout_folders workout_sections workout_exercises
    exercise_variations assigned_workouts assigned_workout_athletes
    membership_packages memberships membership_package_subscriptions
    membership_payments promotion_campaigns promotion_codes promotion_redemptions
    referral_programs referral_events referral_rewards finance_invoices
    finance_invoice_lines finance_payment_reversals finance_credit_ledger_entries
    finance_entitlement_usage_entries finance_settings
    review_questionnaires reviews review_answers
    messaging_threads
    messaging_participants messaging_messages seasonal_challenges
    user_challenge_progress challenge_leaderboard_opt_ins leaderboard_opt_ins
    gamification_settings attendance_records communication_threads
    communication_messages analytics_events notification_click_events
    push_dispatch_attempts
  )

  @transitional_tenant_tables []

  @ready_personal_tables ~w(
    workout_executions execution_progress_operations notifications push_subscriptions
    user_pr_records user_stats user_achievements user_gamification_preferences
    injury_reports
  )

  def report do
    %{
      ready: Enum.map(@ready_tenant_tables, &table_status(&1, :organization_id)),
      ready_personal: Enum.map(@ready_personal_tables, &table_status(&1, :user_id)),
      transitional: Enum.map(@transitional_tenant_tables, &table_status(&1, :organization_id))
    }
  end

  def ready_for_full_enforcement?(report \\ report()) do
    Enum.all?(report.ready, &enforced?/1) and
      Enum.all?(report.ready_personal, &enforced?/1) and
      Enum.all?(report.transitional, &enforced?/1)
  end

  defp enforced?(status),
    do: status.unmapped_rows == 0 and status.rls_enabled and status.rls_forced

  defp table_status(table, ownership_column) do
    %{rows: [[unmapped_rows]]} =
      Ecto.Adapters.SQL.query!(
        Repo,
        "SELECT count(*) FROM #{table} WHERE #{ownership_column} IS NULL",
        []
      )

    %{rows: [[rls_enabled, rls_forced]]} =
      Ecto.Adapters.SQL.query!(
        Repo,
        "SELECT relrowsecurity, relforcerowsecurity FROM pg_class WHERE oid = to_regclass($1)",
        [table]
      )

    %{
      table: table,
      unmapped_rows: unmapped_rows,
      rls_enabled: rls_enabled,
      rls_forced: rls_forced
    }
  end
end
