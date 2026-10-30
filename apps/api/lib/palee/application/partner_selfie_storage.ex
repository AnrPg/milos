defmodule Palee.Application.PartnerSelfieStorage do
  @moduledoc """
  The selfie of the Palee check (ADR-280 §3) in the private documents
  bucket, under the person's own prefix
  `users/<user id>/partner-verification/`: a presigned PUT, the probe of the
  uploaded bytes, a 5-minute presigned GET for the Palee team, and
  deletion. Keys outside that prefix are refused.
  """

  require Logger

  @bucket :documents
  @view_seconds 300

  def view_seconds, do: @view_seconds

  @doc "Presigned PUT for the person's own selfie key."
  def upload(user_id, key, content_type) do
    with :ok <- own(user_id, key) do
      case impl().presigned_upload(@bucket, key, content_type) do
        {:ok, presigned} -> {:ok, presigned}
        {:error, _reason} -> {:error, :storage_unavailable}
      end
    end
  end

  @doc "Leading bytes and size of the uploaded selfie."
  def probe(user_id, key, bytes) do
    with :ok <- own(user_id, key) do
      case impl().probe_object(@bucket, key, bytes) do
        {:ok, probe} -> {:ok, probe}
        {:error, :not_found} -> {:error, :partner_selfie_missing}
        {:error, _reason} -> {:error, :storage_unavailable}
      end
    end
  end

  @doc "A 5-minute link to look at the selfie (the Palee team only)."
  def view_url(user_id, key) do
    with :ok <- own(user_id, key) do
      case impl().presigned_object_url(@bucket, key, @view_seconds) do
        {:ok, url} -> {:ok, url}
        {:error, _reason} -> {:error, :storage_unavailable}
      end
    end
  end

  @doc "Deletes selfies, best effort: a failure is logged, never raised."
  def delete(_user_id, []), do: :ok

  def delete(user_id, keys) when is_list(keys) do
    keys = Enum.filter(keys, &(is_binary(&1) and own(user_id, &1) == :ok))

    case keys != [] && impl().delete_objects(@bucket, keys) do
      false ->
        :ok

      {:ok, _count} ->
        :ok

      {:error, reason} ->
        Logger.warning("partner_selfie_delete_failed reason=#{inspect(reason)}")
        :ok
    end
  end

  def delete(user_id, key) when is_binary(key), do: delete(user_id, [key])
  def delete(_user_id, nil), do: :ok

  @doc """
  Deletes every object of one request (`request_id`), or of all the
  person's requests (`:all`), including uploads never submitted. Best
  effort.
  """
  def delete_under(user_id, request_id_or_all) do
    sub = if request_id_or_all == :all, do: "", else: request_id_or_all

    case impl().list_objects(@bucket, prefix(user_id) <> sub) do
      {:ok, objects} ->
        delete(user_id, Enum.map(objects, & &1.key))

      {:error, reason} ->
        Logger.warning("partner_selfie_list_failed reason=#{inspect(reason)}")
        :ok
    end
  end

  @doc "The prefix every selfie key of the person starts with."
  def prefix(user_id), do: "users/#{user_id}/partner-verification/"

  defp own(user_id, key) when is_binary(user_id) and is_binary(key) do
    if String.starts_with?(key, prefix(user_id)) and not String.contains?(key, ".."),
      do: :ok,
      else: {:error, :document_key_forbidden}
  end

  defp own(_user_id, _key), do: {:error, :document_key_forbidden}

  defp impl, do: Application.fetch_env!(:palee, :tenant_object_store)
end
