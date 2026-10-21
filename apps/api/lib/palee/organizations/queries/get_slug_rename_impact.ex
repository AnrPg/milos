defmodule Palee.Organizations.Queries.GetSlugRenameImpact do
  @moduledoc """
  ADR-122: what a slug rename touches, shown to the vendor before the typed
  confirmation - active members whose bookmarks move, pending invitations
  (their links are token-based and keep working), retired aliases that keep
  redirecting, and whether an open purge currently blocks the rename.
  """
  alias Palee.Infrastructure.Tenancy.RepoContext
  alias Palee.Organizations.{OrganizationStore, PlatformContext}

  def call(context, organization_id, now \\ DateTime.utc_now())

  def call(%PlatformContext{} = context, organization_id, now) when is_binary(organization_id) do
    RepoContext.run(%{user_id: context.user_id}, fn ->
      case OrganizationStore.get_organization_by_id(organization_id) do
        nil ->
          {:error, :not_found}

        organization ->
          {:ok,
           %{
             organization: organization,
             active_member_count:
               length(OrganizationStore.list_active_membership_user_ids(organization_id)),
             pending_invitation_count:
               OrganizationStore.count_pending_invitations(organization_id, now),
             aliases: OrganizationStore.list_slug_aliases(organization_id),
             purge_open: not is_nil(OrganizationStore.get_open_purge(organization_id))
           }}
      end
    end)
  end

  def call(%PlatformContext{}, _organization_id, _now), do: {:error, :not_found}
  def call(_context, _organization_id, _now), do: {:error, :vendor_required}
end
