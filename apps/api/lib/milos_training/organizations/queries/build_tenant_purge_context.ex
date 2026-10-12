defmodule MilosTraining.Organizations.Queries.BuildTenantPurgeContext do
  @moduledoc """
  Builds the only tenant scope accepted by context export/purge functions
  (ADR-117). It exists solely while the purge record is in a working stage
  (`exporting` or `purging`), so ordinary request/job contexts can never reach
  destructive tenant-wide operations.
  """

  alias MilosTraining.Infrastructure.Tenancy.RepoContext
  alias MilosTraining.Organizations.{OrganizationPurge, OrganizationStore, PlatformContext}
  alias MilosTraining.TenantData.PurgeContext

  @working_statuses [:exporting, :purging]

  def call(%PlatformContext{} = context, %OrganizationPurge{status: status} = purge)
      when status in @working_statuses do
    subject_user_ids =
      RepoContext.run(%{user_id: context.user_id}, fn ->
        purge.organization_id
        |> OrganizationStore.list_organization_memberships()
        |> Enum.map(& &1.user_id)
        |> Enum.uniq()
      end)

    {:ok,
     %PurgeContext{
       organization_id: purge.organization_id,
       purge_id: purge.id,
       user_id: context.user_id,
       subject_user_ids: subject_user_ids
     }}
  end

  def call(%PlatformContext{}, %OrganizationPurge{}), do: {:error, :invalid_purge_transition}
  def call(_context, _purge), do: {:error, :vendor_required}
end
