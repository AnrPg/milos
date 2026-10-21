defmodule Palee.Application.OrganizationLogo do
  @moduledoc """
  Shared steps of the ADR-121 tenant logo flow: resolving the acting
  organization, the post-change cleanup of superseded objects, and the staff
  refresh broadcast. The use cases are `RequestOrganizationLogoUpload`,
  `FinalizeOrganizationLogo` and `RemoveOrganizationLogo`.
  """

  require Logger

  alias Palee.Application.{BroadcastUserSync, TenantObjectStorage, TenantStaffRecipients}
  alias Palee.Organizations

  @doc """
  Authorizes the actor and confirms the organization exists, returning the
  organization id every later step is pinned to.
  """
  def resolve_organization(context, organization_id) do
    with {:ok, actor} <- Organizations.authorize_logo_change(context, organization_id),
         {:ok, _settings} <-
           Organizations.get_organization_branding(context, actor.organization_id) do
      {:ok, actor.organization_id}
    end
  end

  @doc """
  After a committed change: delete the superseded object (prefix-pinned, best
  effort - an orphan stays inside the tenant prefix and is removed by the
  ADR-117 purge) and tell tenant staff to refresh branding.
  """
  def after_change(_organization_id, %{event: nil, settings: settings}), do: {:ok, settings}

  def after_change(organization_id, %{
        settings: settings,
        previous_object_key: previous_key
      }) do
    case Organizations.superseded_logo_key(
           organization_id,
           previous_key,
           settings.brand_logo_object_key
         ) do
      nil -> :ok
      key -> delete_objects(organization_id, [key])
    end

    BroadcastUserSync.for_users(
      TenantStaffRecipients.user_ids(organization_id),
      ["organization_branding"],
      reason: "organization_branding_updated"
    )

    {:ok, settings}
  end

  @doc "Best-effort, prefix-pinned delete; failures are logged, never raised."
  def delete_objects(organization_id, keys) do
    case TenantObjectStorage.delete_branding_objects(organization_id, keys) do
      {:ok, _deleted} ->
        :ok

      {:error, reason} ->
        Logger.warning(
          "brand_logo_cleanup_failed organization_id=#{organization_id} reason=#{inspect(reason)}"
        )

        :ok
    end
  end
end
