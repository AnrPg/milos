defmodule MilosTraining.Repo.Migrations.RemoveAutoProvisionedVendorMemberships do
  use Ecto.Migration

  def up do
    execute("""
    DELETE FROM organization_memberships AS membership
    USING vendors, organization_provisioning_events AS event
    WHERE vendors.user_id = membership.user_id
      AND vendors.status = 'active'
      AND membership.role = 'owner'
      AND membership.invited_by_user_id = membership.user_id
      AND event.organization_id = membership.organization_id
      AND event.vendor_user_id = membership.user_id
      AND event.event = 'organization_provisioned'
      AND event.metadata->>'provisioning_owner_membership' = 'true'
    """)
  end

  def down do
    :ok
  end
end
