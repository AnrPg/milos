defmodule MilosTraining.Infrastructure.Tenancy.AuditTest do
  @moduledoc """
  F-13: the audit only ever inspected tables someone had remembered to add to
  a hardcoded list, so it reported "complete" while saying nothing about root
  tenant tables, `users`, materialized views, or any newly added tenant table.
  """
  use MilosTraining.DataCase, async: false

  alias MilosTraining.Infrastructure.Tenancy.Audit

  test "every table carrying organization_id is classified" do
    # This is the check that makes the audit self-maintaining: add a tenant
    # table and forget to classify it, and this fails rather than silently
    # excluding it from enforcement.
    assert Audit.unclassified_tables() == []
  end

  test "no RLS policy falls back to the legacy organization" do
    # Regression guard for P1.1/F-04. A reintroduced
    # COALESCE(..., milos_legacy_organization_id()) makes every policy it
    # appears in fail open.
    assert Audit.legacy_fallback_policies() == []
  end

  test "root tenant tables are reported as explicitly classified rather than omitted" do
    report = Audit.report()
    tables = Enum.map(report.platform_administered, & &1.table)

    for table <- ~w(organizations organization_memberships users vendors) do
      assert table in tables
    end

    assert Enum.all?(report.platform_administered, & &1.exempt)
  end

  test "root tenant tables carry real RLS now that the circularity is resolved (F-16)" do
    report = Audit.report()
    by_table = Map.new(report.platform_administered, &{&1.table, &1})

    for table <- ~w(organizations organization_memberships organization_settings
                     organization_domains registration_invitations vendors
                     organization_provisioning_events) do
      status = Map.fetch!(by_table, table)
      assert status.rls_enabled, "#{table} should have RLS enabled"
      assert status.rls_forced, "#{table} should force RLS"
    end

    # users is the deliberate exception (F-08): its policy would have to run
    # before any session context exists, so it stays application-layer-only.
    refute Map.fetch!(by_table, "users").rls_enabled
  end

  test "materialized views are reported, with RLS marked inapplicable" do
    report = Audit.report()
    views = Enum.map(report.materialized_views, & &1.view)

    assert "finance_aggregates" in views
    assert "weekly_leaderboard" in views
    assert Enum.all?(report.materialized_views, &(&1.rls_applicable == false))
    assert Enum.all?(report.materialized_views, & &1.present)
  end

  test "enforcement readiness accounts for the new checks" do
    report = Audit.report()

    assert Audit.ready_for_full_enforcement?(report)

    refute Audit.ready_for_full_enforcement?(%{report | unclassified_tables: ["some_new_table"]})

    refute Audit.ready_for_full_enforcement?(%{
             report
             | legacy_fallback_policies: [%{table: "bookings", policy: "bookings_policy"}]
           })
  end
end
