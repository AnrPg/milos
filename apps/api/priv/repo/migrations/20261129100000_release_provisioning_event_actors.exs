defmodule Palee.Repo.Migrations.ReleaseProvisioningEventActors do
  use Ecto.Migration

  # A gym owner's own logo change is logged as a provisioning event with the
  # owner as actor. The RESTRICT reference then blocked deleting that owner's
  # account, so a vendor could neither purge nor delete the organization
  # (user_has_restricted_history). Deleting an account now clears the actor;
  # the event itself stays until the organization goes.
  def up do
    execute "ALTER TABLE organization_provisioning_events ALTER COLUMN vendor_user_id DROP NOT NULL"

    execute "ALTER TABLE organization_provisioning_events DROP CONSTRAINT organization_provisioning_events_vendor_user_id_fkey"

    execute """
    ALTER TABLE organization_provisioning_events
      ADD CONSTRAINT organization_provisioning_events_vendor_user_id_fkey
      FOREIGN KEY (vendor_user_id) REFERENCES users(id) ON DELETE SET NULL
    """
  end

  def down do
    execute "DELETE FROM organization_provisioning_events WHERE vendor_user_id IS NULL"

    execute "ALTER TABLE organization_provisioning_events DROP CONSTRAINT organization_provisioning_events_vendor_user_id_fkey"

    execute """
    ALTER TABLE organization_provisioning_events
      ADD CONSTRAINT organization_provisioning_events_vendor_user_id_fkey
      FOREIGN KEY (vendor_user_id) REFERENCES users(id) ON DELETE RESTRICT
    """

    execute "ALTER TABLE organization_provisioning_events ALTER COLUMN vendor_user_id SET NOT NULL"
  end
end
