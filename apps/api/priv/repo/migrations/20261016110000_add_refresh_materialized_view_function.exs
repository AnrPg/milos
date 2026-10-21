defmodule Palee.Repo.Migrations.AddRefreshMaterializedViewFunction do
  use Ecto.Migration

  # TD-092 / ADR-131: `REFRESH MATERIALIZED VIEW` requires ownership of the
  # view. The three aggregate views are created (and owned) by the migration
  # role, while the application connects as the non-owner runtime role
  # (`milos_runtime`), so every refresh - RefreshLeaderboardJob, the inline
  # refresh after a leaderboard opt-in, RefreshCoachingAggregatesJob,
  # RefreshFinanceAggregatesJob - failed with "must be owner of materialized
  # view" in production and the leaderboard / dashboards never moved.
  #
  # This SECURITY DEFINER function refreshes one of an explicit allow-list of
  # views as their owner. It takes no data in and returns none: a refresh only
  # recomputes the platform-wide aggregate, and every read of the views stays
  # filtered by the session's organization in the application stores. The
  # refresh query runs as the view owner, exactly as the migration-time
  # `REFRESH MATERIALIZED VIEW` already does.
  def up do
    execute("""
    CREATE OR REPLACE FUNCTION palee_refresh_materialized_view(view_name text)
    RETURNS void
    LANGUAGE plpgsql
    VOLATILE
    SECURITY DEFINER
    SET search_path = public, pg_temp
    AS $$
    BEGIN
      IF view_name IS NULL
         OR view_name NOT IN ('weekly_leaderboard', 'coaching_aggregates', 'finance_aggregates') THEN
        RAISE EXCEPTION 'materialized view % cannot be refreshed through palee_refresh_materialized_view', view_name
          USING ERRCODE = 'insufficient_privilege';
      END IF;

      BEGIN
        EXECUTE format('REFRESH MATERIALIZED VIEW CONCURRENTLY public.%I', view_name);
      EXCEPTION
        -- never populated yet, or no unique index: fall back to a blocking refresh
        WHEN feature_not_supported OR object_not_in_prerequisite_state THEN
          EXECUTE format('REFRESH MATERIALIZED VIEW public.%I', view_name);
      END;
    END
    $$
    """)

    # EXECUTE stays with PUBLIC (the default), like the other palee_*
    # SECURITY DEFINER helpers: runtime roles are provisioned outside
    # migrations under deployment-specific names, and the body only ever
    # refreshes the allow-listed views.
  end

  def down do
    execute("DROP FUNCTION IF EXISTS palee_refresh_materialized_view(text)")
  end
end
