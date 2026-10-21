defmodule Palee.Application.ResumeOrganizationPurge do
  @moduledoc """
  Re-enqueues the background stage of an open purge whose job failed or never
  ran. Both stages are idempotent and unique per purge, so a duplicate resume
  is harmless.
  """

  alias Palee.Application.TenantPurgeJobs
  alias Palee.Organizations

  def call(platform_context, organization_id) do
    with {:ok, purge} <- Organizations.get_organization_purge(platform_context, organization_id),
         {:ok, stage} <- Organizations.purge_resume_stage(purge),
         {:ok, _job} <- TenantPurgeJobs.enqueue(stage, purge.id, platform_context.user_id) do
      {:ok, purge}
    end
  end
end
