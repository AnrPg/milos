defmodule Palee.Application.CancelOrganizationPurge do
  @moduledoc """
  Cancels a not-yet-approved purge and deletes the export bundle and retention
  archive it produced. The organization stays suspended until a vendor
  reactivates it explicitly.
  """

  alias Palee.Application.TenantObjectStorage
  alias Palee.Organizations
  alias Palee.TenantData.Domain.RetentionReview

  def call(platform_context, organization_id) do
    with {:ok, purge} <-
           Organizations.cancel_organization_purge(platform_context, organization_id),
         {:ok, _deleted} <-
           TenantObjectStorage.delete_tenant_objects_under(
             purge.organization_id,
             RetentionReview.export_object_prefix(purge.id)
           ),
         {:ok, _deleted} <-
           TenantObjectStorage.delete_tenant_objects_under(
             purge.organization_id,
             RetentionReview.retained_archive_prefix(purge.id)
           ) do
      {:ok, purge}
    end
  end
end
