defmodule Palee.Application.GetOrganizationPurgeStatus do
  @moduledoc """
  Latest purge record for an organization plus, while the export still exists
  (from export until the purge's storage step removes it, including a failed
  purge), a short-lived signed download URL.
  Works after completion too, because purge records outlive the tenant.
  """

  alias Palee.Application.TenantObjectStorage
  alias Palee.Organizations

  @downloadable [:exported, :approved, :purging, :failed]

  def call(platform_context, organization_id) do
    with {:ok, purge} <- Organizations.get_organization_purge(platform_context, organization_id),
         {:ok, url} <- download_url(purge) do
      {:ok, %{purge: purge, export_download_url: url}}
    end
  end

  defp download_url(%{status: status, export_key: key, organization_id: organization_id})
       when status in @downloadable and is_binary(key),
       do: TenantObjectStorage.tenant_download_url(organization_id, key)

  defp download_url(_purge), do: {:ok, nil}
end
