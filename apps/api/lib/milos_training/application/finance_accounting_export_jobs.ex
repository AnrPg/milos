defmodule MilosTraining.Application.FinanceAccountingExportJobs do
  @moduledoc """
  Enqueues the ADR-108 background accounting export. The job carries only
  the organization and run ids; the worker re-resolves the tenant (an
  inactive organization stops the export).
  """

  alias MilosTraining.Workers.BuildFinanceAccountingExportJob

  def enqueue(organization_id, export_id)
      when is_binary(organization_id) and is_binary(export_id) do
    %{"organization_id" => organization_id, "export_id" => export_id}
    |> BuildFinanceAccountingExportJob.new()
    |> Oban.insert()
  rescue
    RuntimeError -> {:error, :export_job_unavailable}
  end
end
