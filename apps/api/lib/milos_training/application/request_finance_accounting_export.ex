defmodule MilosTraining.Application.RequestFinanceAccountingExport do
  @moduledoc """
  Starts an accounting export for an inclusive date range (ADR-116).

  The run is recorded first (who, when, range, mode) so every attempt is
  auditable. Ranges up to #{MilosTraining.Finance.Domain.AccountingExport.inline_max_days()}
  days are built in the request; longer ranges are queued as an Oban job and
  the caller receives the `queued` run. If background processing cannot be
  reached the run is marked `failed` and `:export_job_unavailable` returned.
  """

  alias MilosTraining.Application.{BuildFinanceAccountingExport, FinanceAccountingExportJobs}
  alias MilosTraining.Finance
  alias MilosTraining.Finance.Domain.AccountingExport

  def call(%{organization_id: organization_id} = context, actor_id, params)
      when is_binary(organization_id) do
    params = params || %{}

    with {:ok, range} <-
           AccountingExport.validate_range(
             value(params, "range_start", :range_start),
             value(params, "range_end", :range_end),
             Date.utc_today()
           ),
         {:ok, export} <-
           Finance.create_accounting_export(context, %{
             requested_by_id: actor_id,
             range_start: range.range_start,
             range_end: range.range_end,
             status: "queued",
             execution_mode: AccountingExport.execution_mode(range.days),
             schema_version: AccountingExport.schema_version()
           }) do
      dispatch(context, export)
    end
  end

  def call(_context, _actor_id, _params), do: {:error, :organization_context_required}

  defp dispatch(context, %{execution_mode: "inline"} = export),
    do: BuildFinanceAccountingExport.call(context, export.id)

  defp dispatch(context, %{execution_mode: "background"} = export) do
    case FinanceAccountingExportJobs.enqueue(context.organization_id, export.id) do
      {:ok, _job} ->
        {:ok, export}

      {:error, _reason} ->
        Finance.update_accounting_export(context, export.id, %{
          status: "failed",
          error_reason: "export_job_unavailable"
        })

        {:error, :export_job_unavailable}
    end
  end

  defp value(params, key, atom_key), do: Map.get(params, key, Map.get(params, atom_key))
end
