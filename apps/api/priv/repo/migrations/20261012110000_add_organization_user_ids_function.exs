defmodule Palee.Repo.Migrations.AddOrganizationUserIdsFunction do
  use Ecto.Migration

  # TD-046: organization_memberships RLS only admits a vendor, the acting
  # user's own row, or an organization owner/admin. Two legitimate reads were
  # therefore empty under the production runtime role:
  #   * staff fanout triggered by a member (workout notes, injuries, reviews,
  #     assignment changes) or by an Oban job - nobody was notified;
  #   * a member's co-member lookup (tenant user search) - only themselves.
  # This narrow SECURITY DEFINER function returns only active user ids of one
  # organization, optionally filtered by role, and only to a session that
  # already belongs to that organization (tenant scope, membership, or vendor).
  def up do
    execute("""
    CREATE OR REPLACE FUNCTION palee_organization_user_ids(org_id uuid, member_roles text[])
    RETURNS SETOF uuid
    LANGUAGE sql
    STABLE
    SECURITY DEFINER
    SET search_path = public, pg_temp
    AS $$
      SELECT om.user_id
      FROM public.organization_memberships om
      WHERE om.organization_id = org_id
        AND om.status = 'active'
        AND (member_roles IS NULL OR om.role::text = ANY (member_roles))
        AND (
          NULLIF(current_setting('app.organization_id', true), '')::uuid = org_id
          OR EXISTS (
            SELECT 1 FROM public.organization_memberships acting
            WHERE acting.organization_id = org_id
              AND acting.user_id = NULLIF(current_setting('app.user_id', true), '')::uuid
              AND acting.status = 'active'
          )
          OR EXISTS (
            SELECT 1 FROM public.vendors v
            WHERE v.user_id = NULLIF(current_setting('app.user_id', true), '')::uuid
              AND v.status = 'active'
          )
        )
    $$
    """)

    # EXECUTE stays with PUBLIC (the default): runtime roles are provisioned
    # outside migrations under deployment-specific names, and the function body
    # itself enforces that the caller belongs to the organization.
  end

  def down do
    execute("DROP FUNCTION IF EXISTS palee_organization_user_ids(uuid, text[])")
  end
end
