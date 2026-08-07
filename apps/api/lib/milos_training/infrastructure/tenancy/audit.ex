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
    user_pr_history
  )

  @transitional_tenant_tables []

  # Tables that hold the tenancy model itself rather than tenant data. RLS is
  # not applicable to them - resolving a tenant requires reading them before
  # any session GUC is set - but F-13 flagged that omitting them entirely made
  # the audit look complete while saying nothing about them. They are reported
  # explicitly so the exemption is a claim on the record, not an absence.
  @platform_administered_tables ~w(
    organizations organization_memberships organization_settings
    organization_domains registration_invitations vendors users
    organization_provisioning_events
  )

  # Materialized views carry denormalized tenant data but cannot have RLS
  # policies. Their queries must filter on organization_id in application code
  # (see P0.1/F-21/F-22). Reported so a new one cannot be added unnoticed.
  @materialized_views ~w(
    finance_aggregates coaching_aggregates weekly_leaderboard
  )

  @ready_personal_tables ~w(
    workout_executions execution_progress_operations notifications push_subscriptions
    user_pr_records user_stats user_achievements user_gamification_preferences
    injury_reports
  )

  def report do
    %{
      ready: Enum.map(@ready_tenant_tables, &table_status(&1, :organization_id)),
      ready_personal: Enum.map(@ready_personal_tables, &table_status(&1, :user_id)),
      transitional: Enum.map(@transitional_tenant_tables, &table_status(&1, :organization_id)),
      platform_administered: Enum.map(@platform_administered_tables, &platform_table_status/1),
      materialized_views: Enum.map(@materialized_views, &materialized_view_status/1),
      unclassified_tables: unclassified_tables(),
      legacy_fallback_policies: legacy_fallback_policies()
    }
  end

  @doc """
  Tables carrying an `organization_id` that no classification list mentions.

  F-13's root cause was that the audit only ever looked at tables someone had
  remembered to add, so a new tenant table was invisible to it by default.
  """
  def unclassified_tables do
    known = @ready_tenant_tables ++ @transitional_tenant_tables ++ @ready_personal_tables ++
              @platform_administered_tables

    %{rows: rows} =
      Ecto.Adapters.SQL.query!(
        Repo,
        """
        SELECT c.relname
        FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace
        JOIN pg_attribute a ON a.attrelid = c.oid
        WHERE n.nspname = 'public'
          AND c.relkind = 'r'
          AND a.attname = 'organization_id'
          AND NOT a.attisdropped
        ORDER BY c.relname
        """,
        []
      )

    rows |> List.flatten() |> Enum.reject(&(&1 in known))
  end

  @doc """
  RLS policies still falling back to the legacy organization.

  P1.1/F-04 removed these; this is the regression guard, since a
  COALESCE(..., milos_legacy_organization_id()) reintroduced anywhere silently
  makes every policy it appears in fail open.
  """
  def legacy_fallback_policies do
    %{rows: rows} =
      Ecto.Adapters.SQL.query!(
        Repo,
        """
        SELECT tablename, policyname
        FROM pg_policies
        WHERE schemaname = 'public'
          AND (COALESCE(qual, '') ILIKE '%milos_legacy_organization_id%'
               OR COALESCE(with_check, '') ILIKE '%milos_legacy_organization_id%')
        ORDER BY tablename, policyname
        """,
        []
      )

    Enum.map(rows, fn [table, policy] -> %{table: table, policy: policy} end)
  end

  def ready_for_full_enforcement?(report \\ report()) do
    Enum.all?(report.ready, &enforced?/1) and
      Enum.all?(report.ready_personal, &enforced?/1) and
      Enum.all?(report.transitional, &enforced?/1) and
      report.unclassified_tables == [] and
      report.legacy_fallback_policies == []
  end

  defp enforced?(status),
    do: status.unmapped_rows == 0 and status.rls_enabled and status.rls_forced

  defp platform_table_status(table) do
    %{rows: [[rls_enabled, rls_forced]]} = rls_flags(table)

    %{table: table, rls_enabled: rls_enabled, rls_forced: rls_forced, exempt: true}
  end

  defp materialized_view_status(view) do
    %{rows: [[exists]]} =
      Ecto.Adapters.SQL.query!(
        Repo,
        "SELECT count(*) FROM pg_matviews WHERE schemaname = 'public' AND matviewname = $1",
        [view]
      )

    # Deliberately not an enforcement gate: matviews cannot carry RLS, so the
    # only honest thing to report is that they exist and rely on query-layer
    # filtering.
    %{view: view, present: exists > 0, rls_applicable: false}
  end

  defp rls_flags(table) do
    Ecto.Adapters.SQL.query!(
      Repo,
      "SELECT relrowsecurity, relforcerowsecurity FROM pg_class WHERE oid = to_regclass($1)",
      [table]
    )
  end

  defp table_status(table, ownership_column) do
    %{rows: [[unmapped_rows]]} =
      Ecto.Adapters.SQL.query!(
        Repo,
        "SELECT count(*) FROM #{table} WHERE #{ownership_column} IS NULL",
        []
      )

    %{rows: [[rls_enabled, rls_forced]]} = rls_flags(table)

    %{
      table: table,
      unmapped_rows: unmapped_rows,
      rls_enabled: rls_enabled,
      rls_forced: rls_forced
    }
  end
end
