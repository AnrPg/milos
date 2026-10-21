defmodule Palee.Application.MediaStorage do
  @moduledoc """
  Object storage for uploaded media (ADR-148), pinned to the owner's prefix:
  `organizations/<id>/` for a gym's media, `users/<id>/` for a person's.
  Nothing here reads or deletes outside those prefixes.
  """

  alias Palee.Application.OwnershipKeys

  @doc "The storage owner of a media scope in a session context."
  def owner(%{organization_id: organization_id}, :tenant) when is_binary(organization_id),
    do: {:tenant, organization_id}

  def owner(%{user_id: user_id}, :account) when is_binary(user_id), do: {:account, user_id}

  @doc "Full object key for a key relative to the owner's prefix."
  def object_key(owner, relative_key), do: prefix(owner) <> relative_key

  def presigned_upload(owner, bucket, key, content_type) do
    with :ok <- owned(owner, key), do: impl().presigned_upload(bucket, key, content_type)
  end

  def probe(owner, bucket, key, bytes) do
    with :ok <- owned(owner, key), do: impl().probe_object(bucket, key, bytes)
  end

  @doc "Copies an object to a local file (ADR-157)."
  def download(owner, bucket, key, path) do
    with :ok <- owned(owner, key), do: impl().download_object(bucket, key, path)
  end

  @doc "Stores a generated rendition under the owner's prefix."
  def put(owner, bucket, key, body, content_type) do
    with :ok <- owned(owner, key), do: impl().put_object(bucket, key, body, content_type)
  end

  @doc "A URL to show the object: stable for public media, short-lived otherwise."
  def read_url(owner, :media_public, key) do
    with :ok <- owned(owner, key), do: impl().public_object_url(:media_public, key)
  end

  def read_url(owner, bucket, key) do
    with :ok <- owned(owner, key), do: impl().presigned_object_url(bucket, key)
  end

  @doc "Deletes objects grouped by bucket; every key must be the owner's."
  def delete(_owner, []), do: {:ok, 0}

  def delete(owner, objects) when is_list(objects) do
    if Enum.all?(objects, &(owned(owner, &1.key) == :ok)) do
      objects
      |> Enum.group_by(& &1.bucket, & &1.key)
      |> Enum.reduce_while({:ok, 0}, fn {bucket, keys}, {:ok, total} ->
        case impl().delete_objects(bucket, keys) do
          {:ok, deleted} -> {:cont, {:ok, total + deleted}}
          error -> {:halt, error}
        end
      end)
    else
      {:error, :media_key_forbidden}
    end
  end

  @doc "Every media object under a gym's prefix, in both media buckets."
  def list_tenant(organization_id), do: list_all({:tenant, organization_id})

  @doc "Every media object under a person's prefix."
  def list_account(user_id), do: list_all({:account, user_id})

  defp list_all(owner) do
    Enum.reduce_while([:media_public, :media_private], {:ok, []}, fn bucket, {:ok, acc} ->
      case impl().list_objects(bucket, prefix(owner) <> "media/") do
        {:ok, objects} -> {:cont, {:ok, acc ++ Enum.map(objects, &Map.put(&1, :bucket, bucket))}}
        error -> {:halt, error}
      end
    end)
  end

  defp owned(owner, key) when is_binary(key) do
    if String.starts_with?(key, prefix(owner)), do: :ok, else: {:error, :media_key_forbidden}
  end

  defp owned(_owner, _key), do: {:error, :media_key_forbidden}

  defp prefix({:tenant, organization_id}),
    do: OwnershipKeys.tenant_object(%{organization_id: organization_id}, "")

  defp prefix({:account, user_id}), do: OwnershipKeys.user_object(%{user_id: user_id}, "")

  defp impl, do: Application.fetch_env!(:palee, :tenant_object_store)
end
