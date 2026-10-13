defmodule MilosTraining.Repo.Migrations.AllowScopedOrganizationSettingsSelfRead do
  use Ecto.Migration

  # TD-092 / ADR-131: mirrors organizations_scoped_self_read_policy for the
  # organization's settings row. A session scoped to an organization without a
  # user - a per-tenant cron job such as corporate invoicing - could read its
  # organization but not its settings (brand name, default locale), so
  # invoices and reminders went out under the raw organization name in
  # English. Additive, read-only, and limited to the session's own
  # organization; user sessions already read it through membership.
  def up do
    execute("""
    CREATE POLICY organization_settings_scoped_self_read_policy ON organization_settings
      FOR SELECT
      USING (organization_id = NULLIF(current_setting('app.organization_id', true), '')::uuid)
    """)
  end

  def down do
    execute(
      "DROP POLICY IF EXISTS organization_settings_scoped_self_read_policy ON organization_settings"
    )
  end
end
