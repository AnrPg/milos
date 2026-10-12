defmodule MilosTraining.Application.BuildFinanceAccountingExport do
  @moduledoc """
  Builds and stores one accounting export run (ADR-116): reads every dataset
  for the run's range through Finance, adds member display names from
  Identity, bundles CSV + JSON + manifest into a ZIP, stores it under the
  tenant prefix (`organizations/<id>/finance/accounting-exports/<run>/`) and
  records the object key, size, SHA-256, per-file checksums and row counts.

  Idempotent: a completed run is returned unchanged. A failure marks the run
  `failed` with a short reason.
  """

  require Logger

  alias MilosTraining.Application.TenantObjectStorage
  alias MilosTraining.{Finance, Identity}
  alias MilosTraining.Finance.Domain.AccountingExport

  def call(%{organization_id: organization_id} = context, export_id)
      when is_binary(organization_id) do
    case Finance.get_accounting_export(context, export_id) do
      nil -> {:error, :not_found}
      %{status: "completed"} = export -> {:ok, export}
      export -> build(context, export)
    end
  end

  def call(_context, _export_id), do: {:error, :organization_context_required}

  defp build(context, export) do
    {:ok, _running} =
      Finance.update_accounting_export(context, export.id, %{
        status: "running",
        started_at: DateTime.utc_now(),
        error_reason: nil
      })

    rows =
      context
      |> Finance.accounting_export_rows(export.range_start, export.range_end)
      |> with_member_names()

    meta = %{
      export_id: export.id,
      organization_id: context.organization_id,
      range_start: export.range_start,
      range_end: export.range_end,
      generated_at: DateTime.utc_now()
    }

    with {:ok, bundle} <- AccountingExport.bundle(meta, rows),
         {:ok, key} <-
           TenantObjectStorage.put_tenant_object(
             context.organization_id,
             AccountingExport.relative_object_key(export.id),
             bundle.zip,
             "application/zip"
           ) do
      Finance.update_accounting_export(context, export.id, %{
        status: "completed",
        object_key: key,
        byte_size: byte_size(bundle.zip),
        sha256: AccountingExport.sha256(bundle.zip),
        row_counts: bundle.row_counts,
        files: bundle.files,
        completed_at: DateTime.utc_now()
      })
    else
      {:error, reason} -> fail(context, export, reason)
    end
  end

  defp fail(context, export, reason) do
    Logger.warning(
      "finance_accounting_export_failed export_id=#{export.id} reason=#{inspect(reason)}"
    )

    Finance.update_accounting_export(context, export.id, %{
      status: "failed",
      error_reason: failure_code(reason),
      completed_at: DateTime.utc_now()
    })

    {:error, :accounting_export_failed}
  end

  defp failure_code({:object_store_failed, _}), do: "object_store_failed"
  defp failure_code({:accounting_export_bundle_failed, _}), do: "bundle_failed"
  defp failure_code(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp failure_code(_reason), do: "unexpected_error"

  defp with_member_names(rows) do
    names =
      rows
      |> Map.values()
      |> List.flatten()
      |> Enum.map(& &1["member_user_id"])
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()
      |> Identity.list_by_ids()
      |> Map.new(fn user -> {user.id, Map.get(user, :display_nickname) || user.nickname} end)

    Map.new(rows, fn {dataset, dataset_rows} ->
      {dataset,
       Enum.map(dataset_rows, &Map.put(&1, "member_name", Map.get(names, &1["member_user_id"])))}
    end)
  end
end
