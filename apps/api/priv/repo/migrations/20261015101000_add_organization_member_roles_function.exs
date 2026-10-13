defmodule MilosTraining.Repo.Migrations.AddOrganizationMemberRolesFunction do
  use Ecto.Migration

  # TD-092: role-aware staff lookups (coach pickers, manager and capability
  # fanout, coaching-relationship checks, a coach's notes visibility) read other
  # members' role sets. organization_memberships RLS only shows a coach, front
  # desk or job session its own row, so those lookups came back empty under the
  # production runtime role. Like `milos_organization_user_ids/2` (TD-046), this
  # narrow SECURITY DEFINER function returns only the active members' role
  # facts, optionally filtered by role set and/or one user, and only to a
  # session that already belongs to the organization.
  def up do
    execute("""
    CREATE OR REPLACE FUNCTION milos_organization_member_roles(
      org_id uuid,
      member_roles text[],
      member_user_id uuid
    )
    RETURNS TABLE (
      user_id uuid,
      role text,
      roles text[],
      coach_scope text,
      notes_visible_to_admins boolean
    )
    LANGUAGE sql
    STABLE
    SECURITY DEFINER
    SET search_path = public, pg_temp
    AS $$
      SELECT om.user_id, om.role::text, om.roles::text[], om.coach_scope::text,
             om.notes_visible_to_admins
      FROM public.organization_memberships om
      WHERE om.organization_id = org_id
        AND om.status = 'active'
        AND (member_roles IS NULL OR om.roles::text[] && member_roles)
        AND (member_user_id IS NULL OR om.user_id = member_user_id)
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
  end

  def down do
    execute("DROP FUNCTION IF EXISTS milos_organization_member_roles(uuid, text[], uuid)")
  end
end
