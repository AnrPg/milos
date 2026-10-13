defmodule MilosTraining.Workers.BuildFinanceAccountingExportJob do
  @moduledoc "ADR-126: builds a large-range accounting export in the background."

  use Oban.Worker,
    queue: :default,
    max_attempts: 3,
    unique: [period: :infinity, fields: [:worker, :args], keys: [:export_id], states: :incomplete]

  alias MilosTraining.Application.{BuildFinanceAccountingExport, ResolveJobTenantContext}

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{"organization_id" => organization_id, "export_id" => export_id}
      }) do
    with {:ok, context} <- ResolveJobTenantContext.call(organization_id, inspect(__MODULE__)),
         {:ok, _export} <- BuildFinanceAccountingExport.call(context, export_id) do
      :ok
    else
      {:error, reason} when reason in [:not_found, :organization_not_found] -> {:cancel, reason}
      {:error, reason} -> {:error, reason}
    end
  end

  def perform(%Oban.Job{}), do: {:cancel, :missing_organization_scope}
end
