defmodule MilosTraining.Application.FinalizeOrganizationLogo do
  @moduledoc """
  ADR-103: verifies an uploaded tenant logo and makes it the organization's
  logo.

  Order matters: the key must be one this organization's policy issued
  (prefix ownership - an admin of org A can never finalize a key under org
  B), then the stored bytes are probed (magic bytes PNG/JPEG/WebP matching
  the key's extension, size <= 2 MiB). A rejected object is deleted so it
  cannot linger publicly readable. Only then are settings updated (with the
  audit event) and the superseded logo object deleted.
  """

  alias MilosTraining.Application.{OrganizationLogo, TenantObjectStorage}
  alias MilosTraining.Organizations

  def call(context, organization_id, key) when is_binary(key) do
    with {:ok, organization_id} <-
           OrganizationLogo.resolve_organization(context, organization_id),
         :ok <- owned(organization_id, key),
         {:ok, _content_type} <- verify_object(organization_id, key),
         {:ok, url} <- TenantObjectStorage.branding_public_url(key),
         {:ok, result} <-
           Organizations.set_organization_logo(context, organization_id, %{
             object_key: key,
             url: url
           }) do
      OrganizationLogo.after_change(organization_id, result)
    end
  end

  def call(_context, _organization_id, _key), do: {:error, :invalid_brand_logo_upload}

  defp owned(organization_id, key) do
    if Organizations.logo_key_owned?(organization_id, key),
      do: :ok,
      else: {:error, :brand_logo_key_forbidden}
  end

  defp verify_object(organization_id, key) do
    case TenantObjectStorage.probe_branding_object(
           organization_id,
           key,
           Organizations.logo_probe_bytes()
         ) do
      {:ok, probe} ->
        case Organizations.validate_logo_object(key, probe) do
          {:ok, content_type} ->
            {:ok, content_type}

          {:error, reason} ->
            OrganizationLogo.delete_objects(organization_id, [key])
            {:error, reason}
        end

      {:error, :not_found} ->
        {:error, :brand_logo_upload_missing}

      {:error, _reason} ->
        {:error, :brand_logo_storage_unavailable}
    end
  end
end
