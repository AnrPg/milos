defmodule Palee.Application.RequestOrganizationPurge do
  @moduledoc """
  ADR-117 stage 1: records the purge request (suspending an active tenant) and
  enqueues the export job.
  """

  alias Palee.Application.TenantPurgeJobs
  alias Palee.Organizations

  def call(platform_context, organization_id) do
    with {:ok, %{purge: purge}} <-
           Organizations.request_organization_purge(platform_context, organization_id),
         {:ok, _job} <- TenantPurgeJobs.enqueue(:export, purge.id, platform_context.user_id) do
      {:ok, purge}
    end
  end
end
