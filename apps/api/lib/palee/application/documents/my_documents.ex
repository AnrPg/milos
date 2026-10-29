defmodule Palee.Application.Documents.MyDocuments do
  @moduledoc """
  Box › Documents for a client (ADR-252): what is still to sign (mandatory
  first; optional ones only offered), reading and signing the current
  version, the signed documents with their PDF certificates, and the
  client's own health certificate.
  """

  alias Palee.Application.Documents.DocumentViews, as: V
  alias Palee.Application.Documents.HealthCertificateFiles, as: Files
  alias Palee.Application.Documents.DocumentsAdmin
  alias Palee.{Documents, Organizations}
  alias Palee.TimeZones.ZonedTime

  @doc """
  `%{documents, outstanding, health_certificate}`: every published document
  with the client's status, the number of outstanding items (unsigned
  mandatory documents, and a missing or expired health certificate when
  the box requires one).
  """
  def overview(context, now \\ DateTime.utc_now()) do
    user_id = context.user_id
    settings = Documents.settings(context)
    items = Documents.member_items(context, user_id)

    health =
      Documents.health_status(context, user_id, Organizations.local_date(context, now), settings)

    health_outstanding = Documents.health_outstanding(settings, health.status)

    %{
      documents: Enum.map(items, &V.item/1),
      outstanding: Enum.count(items, & &1.outstanding) + if(health_outstanding, do: 1, else: 0),
      health_certificate: %{
        required: settings.health_certificate_required,
        status: health.status,
        certificate: V.certificate(health.certificate)
      }
    }
  end

  @doc "The text to sign now: the current version with its body and content hash."
  def document(context, template_id) do
    with {:ok, %{template: template, version: version}} <-
           Documents.current_version(context, template_id) do
      status =
        context
        |> Documents.member_items(context.user_id)
        |> Enum.find(&(&1.template.id == template.id))

      {:ok,
       %{
         template: V.template(template),
         version: V.version(version),
         status: status && Atom.to_string(status.status)
       }}
    end
  end

  @doc """
  Signs the current version. `params`: version_id, agreed, typed_name
  and/or drawn_signature. `request` carries the evidence of the request:
  `ip_address`, `user_agent` and the signer's `account`.
  """
  def sign(context, template_id, params, request, now \\ DateTime.utc_now()) do
    account = request.account

    signer = %{
      user_id: context.user_id,
      display_name: account && Map.get(account, :nickname),
      nickname: account && Map.get(account, :handle),
      email: account && Map.get(account, :email)
    }

    meta = %{
      ip_address: request[:ip_address],
      user_agent: request[:user_agent],
      business_name: DocumentsAdmin.business_name(context),
      local_signed_at: local_time(context, now)
    }

    input = %{
      version_id: Files.param(params, :version_id),
      agreed: Files.param(params, :agreed),
      typed_name: Files.param(params, :typed_name),
      drawn_signature: Files.param(params, :drawn_signature)
    }

    with {:ok, signature} <- Documents.sign(context, template_id, input, signer, meta, now) do
      {:ok, %{signature: V.signature(signature)}}
    end
  end

  defp local_time(context, now) do
    zone = Organizations.organization_timezone(context.organization_id)
    local = ZonedTime.local(now, zone)
    Calendar.strftime(local, "%d/%m/%Y %H:%M:%S") <> " (#{local.time_zone})"
  end

  @doc "The client's own signatures, newest first."
  def signatures(context) do
    result = Documents.list_signatures(context, %{user_id: context.user_id, limit: 200})
    %{signatures: Enum.map(result.signatures, &V.signature/1), total: result.total}
  end

  @doc "A short-lived link to one of the client's own certificates."
  def evidence(context, signature_id) do
    case Documents.get_signature(context, signature_id) do
      %{user_id: user_id} = signature when user_id == context.user_id ->
        with {:ok, url} <- DocumentsAdmin.evidence_url(context, signature) do
          {:ok,
           %{url: url, sha256: signature.evidence_sha256, byte_size: signature.evidence_byte_size}}
        end

      _ ->
        {:error, :not_found}
    end
  end

  # ── Health certificate ──────────────────────────────────────────────────

  def request_health_upload(context, params),
    do: Files.request_upload(context, context.user_id, Files.param(params, :content_type))

  def complete_health_upload(context, params, now \\ DateTime.utc_now()) do
    with {:ok, certificate} <- Files.complete(context, context.user_id, params, context.user_id, now) do
      {:ok, %{health_certificate: V.certificate(certificate)}}
    end
  end

  def health_file(context, id, now \\ DateTime.utc_now()) do
    with {:ok, certificate} <- own_certificate(context, id) do
      Files.download(context, certificate, context.user_id, now)
    end
  end

  def delete_health_certificate(context, id, now \\ DateTime.utc_now()) do
    with {:ok, certificate} <- own_certificate(context, id),
         {:ok, deleted} <- Files.delete(context, certificate, context.user_id, now) do
      {:ok, %{health_certificate: V.certificate(deleted)}}
    end
  end

  defp own_certificate(context, id) do
    case Documents.get_health_certificate(context, id) do
      %{user_id: user_id} = certificate when user_id == context.user_id -> {:ok, certificate}
      _ -> {:error, :not_found}
    end
  end
end
