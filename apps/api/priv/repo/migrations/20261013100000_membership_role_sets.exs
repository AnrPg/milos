defmodule Palee.Repo.Migrations.MembershipRoleSets do
  use Ecto.Migration

  # ADR-099: memberships hold a set of roles; `role` stays as the primary
  # (most privileged) role. ADR-100/101: coach scope and notes visibility.
  @roles ~w(owner admin coach front_desk accountant janitor member athlete)
  @old_roles ~w(owner admin coach member athlete)

  def up do
    alter table(:organization_memberships) do
      add :roles, {:array, :string}, null: false, default: []
      add :coach_scope, :string, null: false, default: "own"
      add :notes_visible_to_admins, :boolean, null: false, default: true
    end

    execute("UPDATE organization_memberships SET roles = ARRAY[role]")

    # Writers that set only `role` (legacy paths, SQL fixtures) get it as the set.
    execute("""
    CREATE OR REPLACE FUNCTION palee_membership_default_roles() RETURNS trigger AS $$
    BEGIN
      IF NEW.roles IS NULL OR cardinality(NEW.roles) = 0 THEN
        NEW.roles := ARRAY[NEW.role]::varchar[];
      END IF;
      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql;
    """)

    execute("""
    CREATE TRIGGER organization_memberships_default_roles
    BEFORE INSERT OR UPDATE ON organization_memberships
    FOR EACH ROW EXECUTE FUNCTION palee_membership_default_roles()
    """)

    drop constraint(:organization_memberships, :organization_memberships_role_check)

    create constraint(:organization_memberships, :organization_memberships_role_check,
             check: "role IN (#{quoted(@roles)})"
           )

    create constraint(:organization_memberships, :organization_memberships_roles_check,
             check: "cardinality(roles) > 0 AND roles <@ ARRAY[#{quoted(@roles)}]::varchar[]"
           )

    create constraint(:organization_memberships, :organization_memberships_coach_scope_check,
             check: "coach_scope IN ('own', 'all')"
           )

    execute(
      "CREATE INDEX organization_memberships_roles_index ON organization_memberships USING gin (roles)"
    )

    drop constraint(:registration_invitations, :registration_invitations_role_check)

    create constraint(:registration_invitations, :registration_invitations_role_check,
             check: "role IN (#{quoted(@roles)})"
           )

    administers(~s|om.roles && ARRAY['owner', 'admin']::varchar[]|)
    execution_policy(~s|om.roles && ARRAY['owner', 'admin', 'coach']::varchar[]|)
  end

  def down do
    execution_policy("om.role IN ('owner', 'admin', 'coach')")
    administers("om.role IN ('owner', 'admin')")

    drop constraint(:registration_invitations, :registration_invitations_role_check)

    execute(
      "UPDATE registration_invitations SET role = 'member' WHERE role NOT IN (#{quoted(@old_roles)})"
    )

    create constraint(:registration_invitations, :registration_invitations_role_check,
             check: "role IN (#{quoted(@old_roles)})"
           )

    execute("DROP INDEX IF EXISTS organization_memberships_roles_index")

    execute(
      "DROP TRIGGER IF EXISTS organization_memberships_default_roles ON organization_memberships"
    )

    execute("DROP FUNCTION IF EXISTS palee_membership_default_roles()")
    drop constraint(:organization_memberships, :organization_memberships_coach_scope_check)
    drop constraint(:organization_memberships, :organization_memberships_roles_check)
    drop constraint(:organization_memberships, :organization_memberships_role_check)

    execute(
      "UPDATE organization_memberships SET role = 'member' WHERE role NOT IN (#{quoted(@old_roles)})"
    )

    create constraint(:organization_memberships, :organization_memberships_role_check,
             check: "role IN (#{quoted(@old_roles)})"
           )

    alter table(:organization_memberships) do
      remove :roles
      remove :coach_scope
      remove :notes_visible_to_admins
    end
  end

  defp quoted(roles), do: Enum.map_join(roles, ", ", &"'#{&1}'")

  defp administers(condition) do
    execute("""
    CREATE OR REPLACE FUNCTION palee_acting_user_administers(org_id uuid) RETURNS boolean AS $$
      SELECT EXISTS (
        SELECT 1 FROM public.organization_memberships om
        WHERE om.organization_id = org_id
          AND om.user_id = NULLIF(current_setting('app.user_id', true), '')::uuid
          AND om.status = 'active'
          AND #{condition}
      )
    $$ LANGUAGE sql STABLE;
    """)
  end

  defp execution_policy(condition) do
    execute(
      "DROP POLICY IF EXISTS workout_executions_owner_or_tenant_policy ON workout_executions"
    )

    execute("""
    CREATE POLICY workout_executions_owner_or_tenant_policy ON workout_executions
    USING (
      user_id = NULLIF(current_setting('app.user_id', true), '')::uuid
      OR organization_id = NULLIF(current_setting('app.organization_id', true), '')::uuid
      OR (
        current_setting('app.admin_mode', true) = 'true'
        AND EXISTS (
          SELECT 1
          FROM organization_memberships om
          WHERE om.organization_id = workout_executions.organization_id
            AND om.user_id = NULLIF(current_setting('app.user_id', true), '')::uuid
            AND #{condition}
            AND om.status = 'active'
        )
      )
      OR current_setting('app.execution_authorization_check', true) = 'true'
    )
    WITH CHECK (user_id = NULLIF(current_setting('app.user_id', true), '')::uuid)
    """)
  end
end
