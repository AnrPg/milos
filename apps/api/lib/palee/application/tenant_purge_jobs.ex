defmodule Palee.Application.TenantPurgeJobs do
  @moduledoc """
  Enqueues the ADR-117 background stages. Jobs carry only the purge id and the
  acting vendor id; the worker re-resolves the vendor's platform context so a
  revoked vendor cannot keep a purge running.
  """

  alias Palee.Workers.{ExecuteOrganizationPurgeJob, ExportOrganizationTenantDataJob}

  def enqueue(stage, purge_id, actor_user_id)
      when stage in [:export, :purge] and is_binary(purge_id) and is_binary(actor_user_id) do
    args = %{"purge_id" => purge_id, "actor_user_id" => actor_user_id}

    job =
      case stage do
        :export -> ExportOrganizationTenantDataJob.new(args)
        :purge -> ExecuteOrganizationPurgeJob.new(args)
      end

    case Oban.insert(job) do
      {:ok, job} -> {:ok, job}
      {:error, reason} -> {:error, reason}
    end
  rescue
    RuntimeError -> {:error, :purge_job_unavailable}
  end
end
