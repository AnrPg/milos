defmodule MilosTraining.Application.RequestOrganizationLogoUpload do
  @moduledoc """
  ADR-103: issues a presigned PUT for a new tenant logo under
  `organizations/<organization_id>/branding/logo/<uuid>.<ext>`. Mirrors
  `RequestAvatarUpload`: the browser uploads straight to object storage and
  then calls `FinalizeOrganizationLogo` with the returned key.
  """

  alias MilosTraining.Application.{OrganizationLogo, TenantObjectStorage}
  alias MilosTraining.Organizations

  @expires_in 900

  def call(context, organization_id, params) when is_map(params) do
    content_type = params[:content_type] || params["content_type"]
    byte_size = params[:byte_size] || params["byte_size"]

    with {:ok, organization_id} <-
           OrganizationLogo.resolve_organization(context, organization_id),
         {:ok, allocation} <-
           Organizations.allocate_logo_key(organization_id, content_type, byte_size),
         {:ok, upload} <-
           TenantObjectStorage.branding_upload(
             organization_id,
             allocation.key,
             allocation.content_type
           ) do
      {:ok,
       %{
         upload_url: upload.url,
         key: allocation.key,
         required_headers: upload.headers,
         expires_in: @expires_in,
         max_bytes: allocation.max_bytes
       }}
    end
  end

  def call(_context, _organization_id, _params), do: {:error, :invalid_brand_logo_upload}
end
