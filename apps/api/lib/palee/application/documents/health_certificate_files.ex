defmodule Palee.Application.Documents.HealthCertificateFiles do
  @moduledoc """
  The file side of health certificates (ADR-252), shared by the member's
  and the staff's use cases: a presigned upload under
  `organizations/<id>/health-certificates/<user id>/`, the check of the
  uploaded bytes, the record with its dates, a short-lived download link
  (every look is audited) and deletion of row and file.
  """

  require Logger

  alias Palee.Application.TenantObjectStorage
  alias Palee.Documents
  alias Palee.Organizations

  @probe_bytes 16

  @doc "A presigned upload for `owner_id`'s certificate: `{:ok, %{upload_url, ...}}`."
  def request_upload(%{organization_id: organization_id}, owner_id, content_type) do
    with {:ok, upload} <- Documents.validate_health_upload(content_type) do
      key =
        TenantObjectStorage.tenant_object_prefix(organization_id) <>
          Documents.health_relative_key(owner_id, upload.extension)

      case TenantObjectStorage.document_upload(organization_id, key, upload.content_type) do
        {:ok, presigned} ->
          {:ok,
           %{
             upload_url: presigned.url,
             method: "PUT",
             required_headers: presigned.headers,
             file_key: key,
             content_type: upload.content_type,
             max_bytes: upload.max_bytes
           }}

        {:error, _reason} ->
          {:error, :storage_unavailable}
      end
    end
  end

  @doc """
  Records an uploaded certificate after checking the file: `params` holds
  file_key, content_type, issued_on and (optionally) expires_on.
  """
  def complete(context, owner_id, params, actor_id, now) do
    file_key = param(params, :file_key)
    content_type = param(params, :content_type)
    prefix = TenantObjectStorage.tenant_object_prefix(context.organization_id)

    with {:ok, _upload} <- Documents.validate_health_upload(content_type),
         true <-
           Documents.health_key_of?(file_key, prefix, owner_id) ||
             {:error, :document_key_forbidden},
         {:ok, probe} <- probe(context, file_key),
         :ok <- Documents.validate_health_file(content_type, probe.head, probe.byte_size) do
      Documents.record_health_certificate(
        context,
        owner_id,
        %{
          issued_on: param(params, :issued_on),
          expires_on: param(params, :expires_on),
          file_key: file_key,
          content_type: content_type,
          byte_size: probe.byte_size
        },
        actor_id,
        Organizations.local_date(context, now),
        now
      )
    end
  end

  defp probe(context, key) do
    case TenantObjectStorage.probe_document_object(context.organization_id, key, @probe_bytes) do
      {:ok, probe} -> {:ok, probe}
      {:error, :not_found} -> {:error, :health_certificate_file_missing}
      {:error, :document_key_forbidden} -> {:error, :document_key_forbidden}
      {:error, _reason} -> {:error, :storage_unavailable}
    end
  end

  @doc "A short-lived link to the file; the look is audited."
  def download(context, certificate, actor_id, now) do
    with {:ok, url} <- link(context, certificate.file_key),
         {:ok, _event} <-
           Documents.audit(
             context,
             "health_certificate_viewed",
             "health_certificate",
             certificate.id,
             actor_id,
             now,
             %{},
             certificate.user_id
           ) do
      {:ok, %{url: url, content_type: certificate.content_type}}
    end
  end

  defp link(context, key) do
    case TenantObjectStorage.tenant_download_url(context.organization_id, key) do
      {:ok, url} -> {:ok, url}
      {:error, _reason} -> {:error, :storage_unavailable}
    end
  end

  @doc "Deletes the row (audited) and then, best effort, the file."
  def delete(context, certificate, actor_id, now) do
    with {:ok, deleted} <-
           Documents.delete_health_certificate(context, certificate.id, actor_id, now) do
      case TenantObjectStorage.delete_document_objects(context.organization_id, [deleted.file_key]) do
        {:ok, _count} ->
          :ok

        {:error, reason} ->
          # The orphan stays inside the tenant prefix; the ADR-117 purge removes it.
          Logger.warning("health_certificate_file_delete_failed reason=#{inspect(reason)}")
      end

      {:ok, deleted}
    end
  end

  def param(params, key) when is_map(params),
    do: Map.get(params, key, Map.get(params, Atom.to_string(key)))

  def param(_params, _key), do: nil
end
