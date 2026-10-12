defmodule MilosTraining.Repo.Migrations.CreateOrganizationSlugAliases do
  use Ecto.Migration

  # ADR-104: a vendor can rename an organization's path slug. Every slug the
  # organization has given up is kept here so bookmarked, shared and stored
  # `/org/<old>/...` links keep resolving (API) and redirecting (web), and so
  # no other organization can claim a retired slug while the organization
  # exists. Rows cascade with the organization, like organization_domains.
  #
  # RLS follows the sibling root tables (organization_domains /
  # organization_settings, 20260807050000): vendors see everything, members
  # see their own organization's aliases (that is what lets tenant resolution
  # by an old slug work under the user-scoped session), plus the invitation
  # carve-out. One extra, narrow carve-out - `app.slug_alias_lookup` - backs
  # the unauthenticated alias lookup the web proxy uses to issue its 308
  # redirect. It is added as separate SELECT-only permissive policies rather
  # than by redefining the existing ones, so this migration stays additive.

  @acting_user "NULLIF(current_setting('app.user_id', true), '')::uuid"

  def up do
    create table(:organization_slug_aliases, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id,
          references(:organizations, type: :binary_id, on_delete: :delete_all),
          null: false

      add :slug, :string, null: false
      add :retired_at, :utc_datetime_usec, null: false
      # Vendor accounts can be removed independently; the provisioning event
      # remains the durable audit record, so no foreign key here.
      add :retired_by_user_id, :binary_id

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:organization_slug_aliases, [:slug])
    create index(:organization_slug_aliases, [:organization_id])

    predicate = """
    milos_acting_user_is_vendor()
    OR milos_acting_user_belongs_to(organization_slug_aliases.organization_id)
    OR current_setting('app.invitation_redemption', true) = 'true'
    """

    execute("""
    CREATE POLICY organization_slug_aliases_tenant_policy ON organization_slug_aliases
    USING (#{predicate})
    WITH CHECK (
      #{@acting_user} IS NULL
      OR #{predicate}
    )
    """)

    execute("""
    CREATE POLICY organization_slug_aliases_lookup_policy ON organization_slug_aliases
    FOR SELECT
    USING (current_setting('app.slug_alias_lookup', true) = 'true')
    """)

    # The alias lookup answers "which canonical slug replaced this one", so it
    # must read organizations.slug for the aliased organization. SELECT only;
    # writes stay governed by organizations_tenant_policy.
    execute("""
    CREATE POLICY organizations_slug_alias_lookup_policy ON organizations
    FOR SELECT
    USING (current_setting('app.slug_alias_lookup', true) = 'true')
    """)

    execute("ALTER TABLE organization_slug_aliases ENABLE ROW LEVEL SECURITY")
    execute("ALTER TABLE organization_slug_aliases FORCE ROW LEVEL SECURITY")
  end

  def down do
    execute("DROP POLICY IF EXISTS organizations_slug_alias_lookup_policy ON organizations")
    drop table(:organization_slug_aliases)
  end
end
