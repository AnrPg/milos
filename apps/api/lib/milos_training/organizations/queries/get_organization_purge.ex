defmodule MilosTraining.Organizations.Queries.GetOrganizationPurge do
  @moduledoc "Vendor-scoped reads of ADR-099 platform purge records."

  alias MilosTraining.Infrastructure.Tenancy.RepoContext
  alias MilosTraining.Organizations.{OrganizationStore, PlatformContext}

  @list_limit 50

  def latest(%PlatformContext{} = context, organization_id) do
    with {:ok, organization_id} <- cast_id(organization_id) do
      RepoContext.run(%{user_id: context.user_id}, fn ->
        case OrganizationStore.get_latest_purge(organization_id) do
          nil -> {:error, :not_found}
          purge -> {:ok, purge}
        end
      end)
    end
  end

  def latest(_context, _organization_id), do: {:error, :vendor_required}

  def by_id(%PlatformContext{} = context, purge_id) do
    with {:ok, purge_id} <- cast_id(purge_id) do
      RepoContext.run(%{user_id: context.user_id}, fn ->
        case OrganizationStore.get_purge(purge_id) do
          nil -> {:error, :not_found}
          purge -> {:ok, purge}
        end
      end)
    end
  end

  def by_id(_context, _purge_id), do: {:error, :vendor_required}

  def list(%PlatformContext{} = context) do
    {:ok,
     RepoContext.run(%{user_id: context.user_id}, fn ->
       OrganizationStore.list_purges(@list_limit)
     end)}
  end

  def list(_context), do: {:error, :vendor_required}

  defp cast_id(id) do
    case Ecto.UUID.cast(id) do
      {:ok, id} -> {:ok, id}
      :error -> {:error, :not_found}
    end
  end
end
