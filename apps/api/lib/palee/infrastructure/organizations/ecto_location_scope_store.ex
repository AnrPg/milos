defmodule Palee.Infrastructure.Organizations.EctoLocationScopeStore do
  @moduledoc """
  Ecto adapter of staff branch scopes (ADR-186).

  Archived branches drop out when a scope is read: the read joins the
  `facility_locations` table by name (no Facility schema is imported) and
  keeps the rows whose location is not archived. The rows themselves stay, so
  un-archiving a branch gives it back to its staff.
  """

  @behaviour Palee.Organizations.Ports.LocationScopeStore

  import Ecto.Query

  alias Palee.Organizations.{MembershipLocationScope, OrganizationMembership}
  alias Palee.Repo

  @impl true
  def location_ids(context, membership_id) do
    context
    |> location_ids_by_membership([membership_id])
    |> Map.get(membership_id, [])
  end

  @impl true
  def location_ids_by_membership(%{organization_id: organization_id}, membership_ids) do
    MembershipLocationScope
    |> join(:inner, [scope], location in "facility_locations",
      on: location.id == scope.location_id and location.organization_id == scope.organization_id
    )
    |> where(
      [scope, location],
      scope.organization_id == ^organization_id and scope.membership_id in ^membership_ids and
        is_nil(location.archived_at)
    )
    |> order_by([scope], asc: scope.location_id)
    |> select([scope], {scope.membership_id, scope.location_id})
    |> Repo.all()
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
  end

  @impl true
  def put_scope(%{organization_id: organization_id}, membership_id, scope) do
    Repo.transaction(fn ->
      membership =
        OrganizationMembership
        |> where([m], m.id == ^membership_id and m.organization_id == ^organization_id)
        |> lock("FOR UPDATE")
        |> Repo.one()

      if is_nil(membership), do: Repo.rollback(:not_found)

      MembershipLocationScope
      |> where([s], s.organization_id == ^organization_id and s.membership_id == ^membership_id)
      |> Repo.delete_all()

      ids = if scope == :all, do: [], else: scope

      Enum.each(ids, fn location_id ->
        %{organization_id: organization_id, membership_id: membership_id, location_id: location_id}
        |> MembershipLocationScope.changeset()
        |> Repo.insert()
        |> case do
          {:ok, _row} -> :ok
          {:error, _changeset} -> Repo.rollback(:invalid_location_scope)
        end
      end)

      membership
      |> OrganizationMembership.location_scope_changeset(scope == :all)
      |> Repo.update()
      |> case do
        {:ok, updated} -> updated
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
  end
end
