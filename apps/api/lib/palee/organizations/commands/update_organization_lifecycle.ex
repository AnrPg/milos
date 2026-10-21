defmodule Palee.Organizations.Commands.UpdateOrganizationLifecycle do
  alias Palee.Infrastructure.Tenancy.RepoContext
  alias Palee.Organizations.{OrganizationStore, PlatformContext}
  alias Palee.Organizations.Domain.PurgePolicy

  @statuses [:active, :suspended, :archived]

  def call(%PlatformContext{} = context, organization_id, status, changed_at) do
    with {:ok, status} <- normalize_status(status) do
      RepoContext.run(%{user_id: context.user_id}, fn ->
        # ADR-117: an open purge pins the lifecycle - approved/running purges
        # cannot be interrupted, and reactivation needs an explicit cancel.
        with :ok <-
               organization_id
               |> open_purge()
               |> PurgePolicy.lifecycle_change_allowed(status) do
          OrganizationStore.update_organization_lifecycle(
            organization_id,
            status,
            context.user_id,
            changed_at
          )
        end
      end)
    end
  end

  def call(_context, _organization_id, _status, _changed_at),
    do: {:error, :vendor_required}

  defp open_purge(organization_id) do
    case Ecto.UUID.cast(organization_id) do
      {:ok, id} -> OrganizationStore.get_open_purge(id)
      :error -> nil
    end
  end

  defp normalize_status(status) when status in @statuses, do: {:ok, status}

  defp normalize_status(status) when is_binary(status) do
    case Enum.find(@statuses, &(Atom.to_string(&1) == status)) do
      nil -> {:error, :invalid_organization_status}
      normalized -> {:ok, normalized}
    end
  end

  defp normalize_status(_status), do: {:error, :invalid_organization_status}
end
