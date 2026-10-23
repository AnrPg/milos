defmodule Palee.Organizations.OrganizationStore do
  @behaviour Palee.Organizations.Ports.OrganizationStore

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
  def get_organization_by_slug_alias(slug), do: impl().get_organization_by_slug_alias(slug)
  @impl true
  def get_canonical_slug_for_alias(slug), do: impl().get_canonical_slug_for_alias(slug)
  @impl true
  def list_slug_aliases(organization_id), do: impl().list_slug_aliases(organization_id)
  @impl true
  def count_pending_invitations(organization_id, now),
    do: impl().count_pending_invitations(organization_id, now)

  @impl true
  def slug_taken?(slug), do: impl().slug_taken?(slug)

  @impl true
  def count_seats(organization_id, now), do: impl().count_seats(organization_id, now)

  @impl true
  def rename_organization_slug(
        organization_id,
        requested_slug,
        confirmation,
        platform_user_id,
        changed_at
      ),
      do:
        impl().rename_organization_slug(
          organization_id,
          requested_slug,
          confirmation,
          platform_user_id,
          changed_at
        )

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
  def list_staff_user_ids(organization_id), do: impl().list_staff_user_ids(organization_id)

  @impl true
  def list_member_roles(organization_id, roles, user_id),
    do: impl().list_member_roles(organization_id, roles, user_id)

  @impl true
  def list_membership_organization_ids(user_ids),
    do: impl().list_membership_organization_ids(user_ids)

  @impl true
  def list_deletable_organization_user_ids(organization_id, platform_user_id),
    do: impl().list_deletable_organization_user_ids(organization_id, platform_user_id)

  @impl true
  def put_organization_settings_entry(organization_id, key, value),
    do: impl().put_organization_settings_entry(organization_id, key, value)

  @impl true
  def put_organization_timezone(organization_id, zone, source),
    do: impl().put_organization_timezone(organization_id, zone, source)

  @impl true
  def list_active_invitations(organization_id, now),
    do: impl().list_active_invitations(organization_id, now)

  @impl true
  def get_invitation_by_digest(digest), do: impl().get_invitation_by_digest(digest)
  @impl true
  def get_invitation_with_organization(digest),
    do: impl().get_invitation_with_organization(digest)

  @impl true
  def grant_vendor(user_id), do: impl().grant_vendor(user_id)

  @impl true
  def revoke_vendor(user_id), do: impl().revoke_vendor(user_id)

  @impl true
  def get_vendor(user_id), do: impl().get_vendor(user_id)

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
  def list_active_organization_ids, do: impl().list_active_organization_ids()

  @impl true
  def delete_organization(organization_id, platform_user_id, deleted_at),
    do: impl().delete_organization(organization_id, platform_user_id, deleted_at)

  @impl true
  def transaction(fun) when is_function(fun, 0), do: impl().transaction(fun)

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
  def rename_organization(organization_id, name, platform_user_id, changed_at),
    do: impl().rename_organization(organization_id, name, platform_user_id, changed_at)

  @impl true
  def record_invitation_email_sent(organization_id, platform_user_id, email_digest),
    do: impl().record_invitation_email_sent(organization_id, platform_user_id, email_digest)

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
  def replace_organization_logo(organization_id, logo, actor, changed_at),
    do: impl().replace_organization_logo(organization_id, logo, actor, changed_at)

  @impl true
  def update_membership_role(organization_id, membership_id, role),
    do: impl().update_membership_role(organization_id, membership_id, role)

  @impl true
  def set_organization_status(organization_id, status),
    do: impl().set_organization_status(organization_id, status)

  @impl true
  def put_organization_setting(organization_id, key, value),
    do: impl().put_organization_setting(organization_id, key, value)

  @impl true
  def update_membership_roles(organization_id, membership_id, roles),
    do: impl().update_membership_roles(organization_id, membership_id, roles)

  @impl true
  def update_membership_settings(organization_id, membership_id, settings),
    do: impl().update_membership_settings(organization_id, membership_id, settings)

  @impl true
  def update_membership_status(organization_id, membership_id, status),
    do: impl().update_membership_status(organization_id, membership_id, status)

  @impl true
  def request_organization_purge(
        organization_id,
        platform_user_id,
        lifecycle_status,
        requested_at
      ),
      do:
        impl().request_organization_purge(
          organization_id,
          platform_user_id,
          lifecycle_status,
          requested_at
        )

  @impl true
  def get_purge(purge_id), do: impl().get_purge(purge_id)

  @impl true
  def lock_purge(purge_id), do: impl().lock_purge(purge_id)

  @impl true
  def get_open_purge(organization_id), do: impl().get_open_purge(organization_id)

  @impl true
  def get_latest_purge(organization_id), do: impl().get_latest_purge(organization_id)

  @impl true
  def list_purges(limit), do: impl().list_purges(limit)

  @impl true
  def update_purge(purge, params), do: impl().update_purge(purge, params)

  @impl true
  def finalize_purge(purge, params, platform_user_id, completed_at),
    do: impl().finalize_purge(purge, params, platform_user_id, completed_at)

  @impl true
  def list_my_providers, do: impl().list_my_providers()

  @impl true
  def list_my_provider_coaches, do: impl().list_my_provider_coaches()

  @impl true
  def get_provider_selection(user_id), do: impl().get_provider_selection(user_id)

  @impl true
  def put_provider_selection(user_id, organization_id),
    do: impl().put_provider_selection(user_id, organization_id)

  @impl true
  def get_provider_kind(organization_id), do: impl().get_provider_kind(organization_id)

  @impl true
  def put_provider_kind(organization_id, kind),
    do: impl().put_provider_kind(organization_id, kind)

  @impl true
  def lock_for_creation(key), do: impl().lock_for_creation(key)

  @impl true
  def provider_kinds(organization_ids), do: impl().provider_kinds(organization_ids)

  defp impl, do: Application.fetch_env!(:palee, :organization_store)
end
