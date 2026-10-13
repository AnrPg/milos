defmodule MilosTraining.Application.TenantObjectStorage do
  @moduledoc """
  Storage-owned tenant object inventory and cleanup (ADR-117).

  Every operation is pinned to an ownership prefix built by `OwnershipKeys`:
  tenant documents live under `organizations/<organization_id>/` in the
  documents bucket and account avatars under `users/<user_id>/` in the avatar
  bucket. Nothing here can list or delete outside those prefixes, which is what
  makes a tenant purge safe without a blind bucket-wide delete.

  ADR-121 tenant logos use the logical `:branding` bucket (the public media
  bucket) under the same `organizations/<organization_id>/` prefix; they are
  inventoried with, and purged like, the tenant's documents.
  """

  alias MilosTraining.Application.OwnershipKeys

  @doc "Objects currently stored for a tenant and for the given accounts."
  def inventory(organization_id, user_ids) when is_binary(organization_id) do
    with {:ok, documents} <- list_tenant_objects(organization_id),
         {:ok, branding} <- list_branding_objects(organization_id),
         {:ok, avatars} <- list_user_objects(user_ids) do
      # Uploaded logos (ADR-121) are tenant objects too; they live in the
      # public media bucket but are purged like any other tenant document.
      {:ok, %{documents: documents ++ branding, avatars: avatars}}
    end
  end

  # --- ADR-121 tenant branding (public media bucket, tenant prefix) ----------

  def list_branding_objects(organization_id) when is_binary(organization_id),
    do: impl().list_objects(:branding, tenant_prefix(organization_id))

  @doc "Presigned PUT for a tenant-owned branding key."
  def branding_upload(organization_id, key, content_type)
      when is_binary(organization_id) and is_binary(key) do
    if String.starts_with?(key, tenant_prefix(organization_id)),
      do: impl().presigned_upload(:branding, key, content_type),
      else: {:error, :brand_logo_key_forbidden}
  end

  @doc "Leading bytes and size of a tenant-owned branding object."
  def probe_branding_object(organization_id, key, bytes)
      when is_binary(organization_id) and is_binary(key) do
    if String.starts_with?(key, tenant_prefix(organization_id)),
      do: impl().probe_object(:branding, key, bytes),
      else: {:error, :brand_logo_key_forbidden}
  end

  def branding_public_url(key) when is_binary(key), do: impl().public_object_url(:branding, key)

  @doc "Deletes tenant-owned branding objects; keys outside the tenant prefix are refused."
  def delete_branding_objects(organization_id, keys)
      when is_binary(organization_id) and is_list(keys) do
    prefix = tenant_prefix(organization_id)

    if Enum.all?(keys, &(is_binary(&1) and String.starts_with?(&1, prefix))),
      do: delete(:branding, Enum.map(keys, &%{key: &1})),
      else: {:error, :brand_logo_key_forbidden}
  end

  def list_tenant_objects(organization_id) when is_binary(organization_id),
    do: impl().list_objects(:documents, tenant_prefix(organization_id))

  def list_user_objects(user_ids) when is_list(user_ids) do
    Enum.reduce_while(user_ids, {:ok, []}, fn user_id, {:ok, acc} ->
      case impl().list_objects(:avatars, user_prefix(user_id)) do
        {:ok, objects} -> {:cont, {:ok, acc ++ objects}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  @doc "Stores an object under the tenant prefix and returns its full key."
  def put_tenant_object(organization_id, relative_path, body, content_type)
      when is_binary(organization_id) and is_binary(body) do
    key = OwnershipKeys.tenant_object(%{organization_id: organization_id}, relative_path)

    case impl().put_object(:documents, key, body, content_type) do
      :ok -> {:ok, key}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Short-lived signed download URL for an object owned by the tenant."
  def tenant_download_url(organization_id, key)
      when is_binary(organization_id) and is_binary(key) do
    if String.starts_with?(key, tenant_prefix(organization_id)),
      do: impl().presigned_object_url(:documents, key),
      else: {:error, :document_key_forbidden}
  end

  def tenant_download_url(_organization_id, _key), do: {:error, :document_key_forbidden}

  @doc """
  Deletes every tenant object except those under the retained tenant-relative
  prefixes. Idempotent: a second run finds only retained objects.
  """
  def purge_tenant_objects(organization_id, retained_relative_prefixes)
      when is_binary(organization_id) and is_list(retained_relative_prefixes) do
    prefix = tenant_prefix(organization_id)
    retained = Enum.map(retained_relative_prefixes, &(prefix <> &1))

    with {:ok, objects} <- list_tenant_objects(organization_id),
         {:ok, branding} <- list_branding_objects(organization_id) do
      {kept, doomed} =
        Enum.split_with(objects, fn %{key: key} ->
          Enum.any?(retained, &String.starts_with?(key, &1))
        end)

      with {:ok, deleted} <- delete(:documents, doomed),
           {:ok, deleted_branding} <- delete(:branding, branding) do
        {:ok, %{deleted_objects: deleted + deleted_branding, retained_objects: length(kept)}}
      end
    end
  end

  @doc "Deletes everything under one tenant-relative prefix (e.g. a cancelled export)."
  def delete_tenant_objects_under(organization_id, relative_prefix)
      when is_binary(organization_id) and is_binary(relative_prefix) and relative_prefix != "" do
    with {:ok, objects} <-
           impl().list_objects(:documents, tenant_prefix(organization_id) <> relative_prefix) do
      delete(:documents, objects)
    end
  end

  @doc "Deletes all objects owned by the given accounts (avatars)."
  def purge_user_objects(user_ids) when is_list(user_ids) do
    with {:ok, objects} <- list_user_objects(user_ids) do
      delete(:avatars, objects)
    end
  end

  defp delete(_bucket, []), do: {:ok, 0}
  defp delete(bucket, objects), do: impl().delete_objects(bucket, Enum.map(objects, & &1.key))

  defp tenant_prefix(organization_id),
    do: OwnershipKeys.tenant_object(%{organization_id: organization_id}, "")

  defp user_prefix(user_id), do: OwnershipKeys.user_object(%{user_id: user_id}, "")

  defp impl, do: Application.fetch_env!(:milos_training, :tenant_object_store)
end
