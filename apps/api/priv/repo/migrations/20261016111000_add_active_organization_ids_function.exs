defmodule Palee.Repo.Migrations.AddActiveOrganizationIdsFunction do
  use Ecto.Migration

  # TD-092 / ADR-131: every per-tenant cron job (payment and package-expiry
  # reminders, subscription expiry, overdue invoices, corporate invoicing,
  # entitlement reconciliation, coaching reply alerts, inventory digests, the
  # abandoned-execution sweep) starts by listing the organizations to visit.
  # A job has no session scope, and the organizations policies only admit a
  # vendor, a member, invitation redemption or a session already scoped to one
  # organization - so under the production runtime role the list was empty and
  # every one of those jobs silently did nothing.
  #
  # This narrow SECURITY DEFINER function returns only the ids of active
  # organizations, nothing else. Each job then enters one organization at a
  # time through its own RepoContext scope, where the regular tenant policies
  # (and the scoped self-read policies) apply.
  def up do
    execute("""
    CREATE OR REPLACE FUNCTION palee_active_organization_ids()
    RETURNS SETOF uuid
    LANGUAGE sql
    STABLE
    SECURITY DEFINER
    SET search_path = public, pg_temp
    AS $$
      SELECT o.id
      FROM public.organizations o
      WHERE o.status = 'active'
      ORDER BY o.name, o.id
    $$
    """)

    # EXECUTE stays with PUBLIC (the default), like the other palee_*
    # SECURITY DEFINER helpers: runtime roles are provisioned outside
    # migrations under deployment-specific names.
  end

  def down do
    execute("DROP FUNCTION IF EXISTS palee_active_organization_ids()")
  end
end
