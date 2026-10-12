defmodule MilosTraining.Application.ApproveOrganizationPurge do
  @moduledoc """
  ADR-117 stage 4: approves an exported purge after the typed slug
  confirmation (recording whether a second vendor approved) and enqueues the
  purge job.
  """

  alias MilosTraining.Application.TenantPurgeJobs
  alias MilosTraining.Organizations

  def call(platform_context, organization_id, params) do
    confirmation = Map.get(params, "confirmation") || Map.get(params, :confirmation)

    with {:ok, purge} <-
           Organizations.approve_organization_purge(
             platform_context,
             organization_id,
             confirmation
           ),
         {:ok, _job} <- TenantPurgeJobs.enqueue(:purge, purge.id, platform_context.user_id) do
      {:ok, purge}
    end
  end
end
