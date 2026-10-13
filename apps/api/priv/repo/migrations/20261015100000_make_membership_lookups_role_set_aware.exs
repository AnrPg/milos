defmodule MilosTraining.Repo.Migrations.MakeMembershipLookupsRoleSetAware do
  use Ecto.Migration

  # ADR-099 gave memberships a role set (`roles`); `role` is only the primary
  # role. The SECURITY DEFINER lookups from TD-046 (staff/co-member ids) and
  # ADR-129 (is the session user a coach of the gym) still matched `role`, so an
  # owner who also coaches was neither notified as a coach nor allowed to read
  # members' PRs. Both now match the role set; signatures are unchanged.
  def up do
    execute("""
    CREATE OR REPLACE FUNCTION milos_organization_user_ids(org_id uuid, member_roles text[])
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
        AND (member_roles IS NULL OR om.roles::text[] && member_roles)
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

    execute("""
    CREATE OR REPLACE FUNCTION milos_acting_user_coaches(org_id uuid)
    RETURNS boolean
    LANGUAGE sql
    STABLE
    SECURITY DEFINER
    SET search_path = public, pg_temp
    AS $$
      SELECT EXISTS (
        SELECT 1
        FROM public.organization_memberships om
        WHERE om.organization_id = org_id
          AND om.user_id = NULLIF(current_setting('app.user_id', true), '')::uuid
          AND om.status = 'active'
          AND 'coach' = ANY (om.roles)
      )
    $$
    """)
  end

  def down do
    execute("""
    CREATE OR REPLACE FUNCTION milos_organization_user_ids(org_id uuid, member_roles text[])
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

    execute("""
    CREATE OR REPLACE FUNCTION milos_acting_user_coaches(org_id uuid)
    RETURNS boolean
    LANGUAGE sql
    STABLE
    SECURITY DEFINER
    SET search_path = public, pg_temp
    AS $$
      SELECT EXISTS (
        SELECT 1
        FROM public.organization_memberships om
        WHERE om.organization_id = org_id
          AND om.user_id = NULLIF(current_setting('app.user_id', true), '')::uuid
          AND om.status = 'active'
          AND om.role = 'coach'
      )
    $$
    """)
  end
end
