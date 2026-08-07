defmodule MilosTraining.Repo.Migrations.EnableRlsOnRootTenantTables do
  use Ecto.Migration

  # F-16 / P3.4: the root tenant tables held the tenancy model itself and had no
  # Row Level Security at all, so a missing application-layer predicate on any
  # of them had no database backstop - unlike every other tenant-owned table.
  #
  # The obstacle was circularity: resolving a tenant means reading
  # `organizations` and `organization_memberships` before any session context
  # exists. That is solved in application code rather than avoided here -
  # ResolveTenantContext and ResolvePlatformContext now run inside a
  # user-scoped RepoContext, so `app.user_id` is set while the tenant is being
  # resolved, and these policies key on it.
  #
  # Invitation inspection and redemption are the one flow where the acting
  # account is legitimately not yet a member, so they run under an explicit
  # `app.invitation_redemption` carve-out, mirroring the existing
  # `app.execution_authorization_check` pattern.

  @acting_user "NULLIF(current_setting('app.user_id', true), '')::uuid"

  def up do
    # A vendor sees everything: platform operators provision and support every
    # organization. Membership below is what scopes ordinary accounts.
    execute("""
    CREATE OR REPLACE FUNCTION milos_acting_user_is_vendor() RETURNS boolean AS $$
      SELECT EXISTS (
        SELECT 1 FROM vendors v
        WHERE v.user_id = #{@acting_user} AND v.status = 'active'
      )
    $$ LANGUAGE sql STABLE;
    """)

    execute("""
    CREATE OR REPLACE FUNCTION milos_acting_user_belongs_to(org_id uuid) RETURNS boolean AS $$
      SELECT EXISTS (
        SELECT 1 FROM organization_memberships om
        WHERE om.organization_id = org_id
          AND om.user_id = #{@acting_user}
          AND om.status = 'active'
      )
    $$ LANGUAGE sql STABLE;
    """)

    execute("""
    CREATE OR REPLACE FUNCTION milos_acting_user_administers(org_id uuid) RETURNS boolean AS $$
      SELECT EXISTS (
        SELECT 1 FROM organization_memberships om
        WHERE om.organization_id = org_id
          AND om.user_id = #{@acting_user}
          AND om.status = 'active'
          AND om.role IN ('owner', 'admin')
      )
    $$ LANGUAGE sql STABLE;
    """)

    # organizations: visible to its own members, to vendors, and during
    # invitation redemption (the invitee is joining it and must be able to read
    # its name/status). See policy/2 below for how writes differ.
    policy(:organizations, """
    milos_acting_user_is_vendor()
    OR milos_acting_user_belongs_to(organizations.id)
    OR current_setting('app.invitation_redemption', true) = 'true'
    """)

    # organization_memberships: an account always sees its own memberships (the
    # organization switcher depends on it); owners/admins see their whole
    # organization's.
    policy(:organization_memberships, """
    milos_acting_user_is_vendor()
    OR organization_memberships.user_id = #{@acting_user}
    OR milos_acting_user_administers(organization_memberships.organization_id)
    OR current_setting('app.invitation_redemption', true) = 'true'
    """)

    for table <- [:organization_settings, :organization_domains] do
      policy(table, """
      milos_acting_user_is_vendor()
      OR milos_acting_user_belongs_to(#{table}.organization_id)
      OR current_setting('app.invitation_redemption', true) = 'true'
      """)
    end

    # registration_invitations: administered by the issuing organization, plus
    # the redemption carve-out for the holder who is not yet a member.
    policy(:registration_invitations, """
    milos_acting_user_is_vendor()
    OR milos_acting_user_administers(registration_invitations.organization_id)
    OR current_setting('app.invitation_redemption', true) = 'true'
    """)

    # vendors: an account may see its own row (that is how vendor status is
    # resolved), and vendors see all.
    policy(:vendors, """
    vendors.user_id = #{@acting_user}
    OR milos_acting_user_is_vendor()
    """)

    # organization_provisioning_events: a write-only vendor audit log, never
    # read back by any application code. Vendor-only, no per-tenant access.
    policy(:organization_provisioning_events, """
    milos_acting_user_is_vendor()
    """)
  end

  def down do
    for table <- [
          :organizations,
          :organization_memberships,
          :organization_settings,
          :organization_domains,
          :registration_invitations,
          :vendors,
          :organization_provisioning_events
        ] do
      execute("ALTER TABLE #{table} DISABLE ROW LEVEL SECURITY")
      execute("ALTER TABLE #{table} NO FORCE ROW LEVEL SECURITY")
      execute("DROP POLICY IF EXISTS #{table}_tenant_policy ON #{table}")
    end

    execute("DROP FUNCTION IF EXISTS milos_acting_user_administers(uuid)")
    execute("DROP FUNCTION IF EXISTS milos_acting_user_belongs_to(uuid)")
    execute("DROP FUNCTION IF EXISTS milos_acting_user_is_vendor()")
  end

  # Reads and writes are governed separately.
  #
  # Reads are the leak vector this finding is about - one tenant seeing
  # another's organization, roster or settings - so USING is strictly scoped.
  #
  # Writes to the root tables were already gated in application code (only
  # vendors provision organizations; only owners/admins issue invitations), and
  # they must remain possible from sessions that have no acting user at all:
  # migrations, seeds, `mix milos.organizations.ensure_legacy`, and the
  # provisioning transaction that creates an organization *before* any
  # membership in it can exist. WITH CHECK therefore blocks the case that
  # matters - an authenticated account writing into an organization it has no
  # standing in - while leaving system paths workable.
  defp policy(table, predicate) do
    execute("DROP POLICY IF EXISTS #{table}_tenant_policy ON #{table}")

    execute("""
    CREATE POLICY #{table}_tenant_policy ON #{table}
    USING (#{predicate})
    WITH CHECK (
      #{@acting_user} IS NULL
      OR #{predicate}
    )
    """)

    execute("ALTER TABLE #{table} ENABLE ROW LEVEL SECURITY")
    execute("ALTER TABLE #{table} FORCE ROW LEVEL SECURITY")
  end
end
