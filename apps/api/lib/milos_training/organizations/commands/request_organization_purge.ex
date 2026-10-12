defmodule MilosTraining.Organizations.Commands.RequestOrganizationPurge do
  @moduledoc """
  Opens a reviewed purge (ADR-099): records the platform purge request and
  suspends an active organization so no tenant session can write while the
  export is taken. Root-table reads/writes run in a vendor-scoped RepoContext.
  """

  alias MilosTraining.Infrastructure.Tenancy.RepoContext
  alias MilosTraining.Organizations.{OrganizationStore, PlatformContext}
  alias MilosTraining.Organizations.Domain.PurgePolicy

  def call(%PlatformContext{} = context, organization_id, requested_at) do
    with {:ok, organization_id} <- Ecto.UUID.cast(organization_id) |> not_found() do
      RepoContext.run(%{user_id: context.user_id}, fn ->
        case OrganizationStore.get_organization_by_id(organization_id) do
          nil ->
            {:error, :not_found}

          organization ->
            OrganizationStore.request_organization_purge(
              organization.id,
              context.user_id,
              PurgePolicy.requested_lifecycle_status(organization.status),
              requested_at
            )
        end
      end)
    end
  end

  def call(_context, _organization_id, _requested_at), do: {:error, :vendor_required}

  defp not_found({:ok, id}), do: {:ok, id}
  defp not_found(:error), do: {:error, :not_found}
end
