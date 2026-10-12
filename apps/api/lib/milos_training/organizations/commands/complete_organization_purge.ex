defmodule MilosTraining.Organizations.Commands.CompleteOrganizationPurge do
  @moduledoc """
  Final ADR-107 step: deletes the organization row (cascading the remaining
  Organizations-owned rows) and marks the platform purge record completed in
  one transaction. Idempotent: an already completed purge is returned as is.
  """

  alias MilosTraining.Infrastructure.Tenancy.RepoContext
  alias MilosTraining.Organizations.{OrganizationPurge, OrganizationStore, PlatformContext}
  alias MilosTraining.Organizations.Domain.PurgePolicy

  def call(%PlatformContext{} = context, purge_id, completed_at) when is_binary(purge_id) do
    RepoContext.run(%{user_id: context.user_id}, fn ->
      OrganizationStore.transaction(fn ->
        case OrganizationStore.lock_purge(purge_id) do
          nil ->
            {:error, :not_found}

          %OrganizationPurge{status: :completed} = purge ->
            {:ok, purge}

          %OrganizationPurge{} = purge ->
            with {:ok, status} <- PurgePolicy.transition(purge, :complete) do
              steps = PurgePolicy.put_step(purge.steps, :organizations, %{}, completed_at)

              OrganizationStore.finalize_purge(
                purge,
                %{status: status, steps: steps, completed_at: completed_at},
                context.user_id,
                completed_at
              )
            end
        end
      end)
    end)
  end

  def call(%PlatformContext{}, _purge_id, _completed_at), do: {:error, :not_found}
  def call(_context, _purge_id, _completed_at), do: {:error, :vendor_required}
end
