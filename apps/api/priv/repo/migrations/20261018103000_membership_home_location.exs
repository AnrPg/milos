defmodule MilosTraining.Repo.Migrations.MembershipHomeLocation do
  @moduledoc """
  Phase 2 (UX decision, 2026-10-17): members, coaches and admins experience
  their gym as one home location; only the owner oversees all of them. The
  home location is a default, not a fence: anyone can still view and book
  another location of the gym.

  The composite key keeps the location inside the membership's gym; deleting a
  location clears only the home location, never the gym.
  """

  use Ecto.Migration

  def up do
    alter table(:organization_memberships) do
      add :home_location_id, :binary_id
    end

    execute("""
    ALTER TABLE organization_memberships
      ADD CONSTRAINT organization_memberships_home_location_fkey
      FOREIGN KEY (home_location_id, organization_id)
      REFERENCES facility_locations (id, organization_id)
      ON DELETE SET NULL (home_location_id)
    """)

    create index(:organization_memberships, [:home_location_id],
             where: "home_location_id IS NOT NULL"
           )

    # The member-roles lookup (TD-092) also answers each member's home location.
    execute("DROP FUNCTION milos_organization_member_roles(uuid, text[], uuid)")

    execute("""
    CREATE FUNCTION milos_organization_member_roles(
      org_id uuid,
      member_roles text[],
      member_user_id uuid
    )
    RETURNS TABLE (
      user_id uuid,
      role text,
      roles text[],
      coach_scope text,
      notes_visible_to_admins boolean,
      home_location_id uuid
    )
    LANGUAGE sql
    STABLE
    SECURITY DEFINER
    SET search_path = public, pg_temp
    AS $$
      SELECT om.user_id, om.role::text, om.roles::text[], om.coach_scope::text,
             om.notes_visible_to_admins, om.home_location_id
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
    execute("DROP FUNCTION milos_organization_member_roles(uuid, text[], uuid)")

    execute("""
    CREATE FUNCTION milos_organization_member_roles(
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

    drop index(:organization_memberships, [:home_location_id])

    execute(
      "ALTER TABLE organization_memberships DROP CONSTRAINT organization_memberships_home_location_fkey"
    )

    alter table(:organization_memberships) do
      remove :home_location_id
    end
  end
end
