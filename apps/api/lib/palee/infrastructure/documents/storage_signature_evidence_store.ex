defmodule Palee.Infrastructure.Documents.StorageSignatureEvidenceStore do
  @moduledoc """
  Simple electronic signatures (ADR-252, port
  `Documents.Ports.SignatureEvidenceStore`): nothing is sealed by a third
  party; the PDF certificate is stored through the tenant object storage at
  `organizations/<id>/documents/evidence/<signature id>.pdf`, kept by the
  ADR-117 retention like the rows that point at it.
  """

  @behaviour Palee.Documents.Ports.SignatureEvidenceStore

  alias Palee.Application.TenantObjectStorage

  @impl true
  def level, do: "simple"

  @impl true
  def provider, do: "palee"

  @impl true
  def seal(_context, pdf, _evidence), do: {:ok, pdf}

  @impl true
  def store(%{organization_id: organization_id}, signature_id, pdf) when is_binary(pdf) do
    path = "documents/evidence/#{signature_id}.pdf"

    case TenantObjectStorage.put_tenant_object(organization_id, path, pdf, "application/pdf") do
      {:ok, key} ->
        {:ok,
         %{
           key: key,
           sha256: :crypto.hash(:sha256, pdf) |> Base.encode16(case: :lower),
           byte_size: byte_size(pdf)
         }}

      {:error, reason} ->
        {:error, {:evidence_storage_failed, reason}}
    end
  end

  @impl true
  def download_url(%{organization_id: organization_id}, key),
    do: TenantObjectStorage.tenant_download_url(organization_id, key)
end
