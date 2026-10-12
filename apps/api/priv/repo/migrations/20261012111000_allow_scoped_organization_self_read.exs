defmodule MilosTraining.Repo.Migrations.AllowScopedOrganizationSelfRead do
  use Ecto.Migration

  # TD-046 / TD-069: organizations RLS admitted only vendors, members (via
  # app.user_id), and invitation redemption, so a session scoped to an
  # organization without a user - every Oban job resolving its system tenant
  # context - could not read its own organization row and failed with
  # :organization_not_found under the production runtime role. This additive,
  # read-only permissive policy lets a session scoped to an organization read
  # exactly that organization's row.
  def up do
    execute("""
    CREATE POLICY organizations_scoped_self_read_policy ON organizations
      FOR SELECT
      USING (id = NULLIF(current_setting('app.organization_id', true), '')::uuid)
    """)
  end

  def down do
    execute("DROP POLICY IF EXISTS organizations_scoped_self_read_policy ON organizations")
  end
end
