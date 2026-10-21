defmodule Palee.Repo.Migrations.AddOrganizationBrandLogoObjectKey do
  use Ecto.Migration

  # ADR-121: first-class tenant logo upload.
  #
  # `brand_logo_object_key` records the storage key of an uploaded logo
  # (`organizations/<organization_id>/branding/logo/<uuid>.<ext>`). The
  # existing `brand_logo_url` column stays the read model every consumer uses;
  # for uploaded logos it holds the derived public media URL.
  #
  # Tenant owners/admins may now record their own logo audit events in
  # `organization_provisioning_events`, which was vendor-only. The extra
  # permissive INSERT policy is narrow: only logo events, only for an
  # organization the acting user administers, and only in the acting user's
  # own name. Reads stay vendor-only (the existing USING clause).

  @acting_user "NULLIF(current_setting('app.user_id', true), '')::uuid"

  def up do
    alter table(:organization_settings) do
      add :brand_logo_object_key, :string
    end

    execute("""
    CREATE POLICY organization_provisioning_events_tenant_logo_insert
    ON organization_provisioning_events
    FOR INSERT
    WITH CHECK (
      organization_provisioning_events.event IN (
        'organization_logo_uploaded',
        'organization_logo_replaced',
        'organization_logo_removed'
      )
      AND organization_provisioning_events.vendor_user_id = #{@acting_user}
      AND palee_acting_user_administers(organization_provisioning_events.organization_id)
    )
    """)
  end

  def down do
    execute(
      "DROP POLICY IF EXISTS organization_provisioning_events_tenant_logo_insert ON organization_provisioning_events"
    )

    alter table(:organization_settings) do
      remove :brand_logo_object_key
    end
  end
end
