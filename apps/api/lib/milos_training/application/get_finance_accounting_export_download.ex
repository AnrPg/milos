defmodule MilosTraining.Application.GetFinanceAccountingExportDownload do
  @moduledoc """
  Short-lived (15 minute) signed download link for a completed accounting
  export (ADR-126). The object key must sit under the tenant's own prefix;
  `TenantObjectStorage` refuses anything else.
  """

  alias MilosTraining.Application.TenantObjectStorage
  alias MilosTraining.Finance

  @expires_in_seconds 900

  def call(%{organization_id: organization_id} = context, export_id)
      when is_binary(organization_id) do
    case Finance.get_accounting_export(context, export_id) do
      nil ->
        {:error, :not_found}

      %{status: "completed", object_key: key} = export when is_binary(key) ->
        with {:ok, url} <- TenantObjectStorage.tenant_download_url(organization_id, key) do
          {:ok,
           %{
             download_url: url,
             file_name: file_name(export),
             sha256: export.sha256,
             byte_size: export.byte_size,
             expires_in_seconds: @expires_in_seconds
           }}
        end

      _export ->
        {:error, :accounting_export_not_ready}
    end
  end

  def call(_context, _export_id), do: {:error, :organization_context_required}

  defp file_name(export),
    do:
      "accounting-export-#{Date.to_iso8601(export.range_start)}-#{Date.to_iso8601(export.range_end)}.zip"
end
