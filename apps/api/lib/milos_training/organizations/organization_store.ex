defmodule MilosTraining.Organizations.OrganizationStore do
  @behaviour MilosTraining.Organizations.Ports.OrganizationStore

  @impl true
  def create_organization(params), do: impl().create_organization(params)
  @impl true
  def add_membership(params), do: impl().add_membership(params)
  @impl true
  def issue_invitation(params, issued_at), do: impl().issue_invitation(params, issued_at)
  @impl true
  def revoke_invitation(organization_id, invitation_id, revoked_at),
    do: impl().revoke_invitation(organization_id, invitation_id, revoked_at)

  @impl true
  def redeem_invitation(digest, user_id, redeemed_at),
    do: impl().redeem_invitation(digest, user_id, redeemed_at)

  @impl true
  def get_organization_by_id(id), do: impl().get_organization_by_id(id)
  @impl true
  def get_organization_by_slug(slug), do: impl().get_organization_by_slug(slug)
  @impl true
  def get_organization_by_domain(host), do: impl().get_organization_by_domain(host)
  @impl true
  def get_membership(organization_id, user_id),
    do: impl().get_membership(organization_id, user_id)

  @impl true
  def get_membership_by_id(organization_id, membership_id),
    do: impl().get_membership_by_id(organization_id, membership_id)

  @impl true
  def list_memberships(user_id), do: impl().list_memberships(user_id)

  @impl true
  def list_organization_memberships(organization_id),
    do: impl().list_organization_memberships(organization_id)

  @impl true
  def list_active_membership_user_ids(organization_id),
    do: impl().list_active_membership_user_ids(organization_id)

  @impl true
  def get_invitation_by_digest(digest), do: impl().get_invitation_by_digest(digest)
  @impl true
  def get_invitation_with_organization(digest),
    do: impl().get_invitation_with_organization(digest)

  @impl true
  def grant_platform_owner(user_id), do: impl().grant_platform_owner(user_id)

  @impl true
  def get_platform_owner(user_id), do: impl().get_platform_owner(user_id)

  @impl true
  def provision_organization(organization_params, invitation_params, platform_user_id, issued_at),
    do:
      impl().provision_organization(
        organization_params,
        invitation_params,
        platform_user_id,
        issued_at
      )

  @impl true
  def list_organizations, do: impl().list_organizations()

  @impl true
  def delete_organization(organization_id, platform_user_id, deleted_at),
    do: impl().delete_organization(organization_id, platform_user_id, deleted_at)

  @impl true
  def update_organization_lifecycle(organization_id, status, platform_user_id, changed_at),
    do:
      impl().update_organization_lifecycle(
        organization_id,
        status,
        platform_user_id,
        changed_at
      )

  @impl true
  def get_organization_settings(organization_id),
    do: impl().get_organization_settings(organization_id)

  @impl true
  def update_organization_settings(organization_id, params, platform_user_id, changed_at),
    do:
      impl().update_organization_settings(
        organization_id,
        params,
        platform_user_id,
        changed_at
      )

  @impl true
  def update_membership_role(organization_id, membership_id, role),
    do: impl().update_membership_role(organization_id, membership_id, role)

  defp impl, do: Application.fetch_env!(:milos_training, :organization_store)
end
