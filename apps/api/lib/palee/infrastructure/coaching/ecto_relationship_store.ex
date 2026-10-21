defmodule Palee.Infrastructure.Coaching.EctoRelationshipStore do
  @moduledoc "Ecto adapter for coaching relationships (ADR-100)."

  @behaviour Palee.Coaching.Ports.RelationshipStore

  import Ecto.Query

  alias Palee.Coaching.Relationship
  alias Palee.Repo

  @impl true
  def start(%{organization_id: organization_id}, attrs) do
    attrs
    |> Map.put(:organization_id, organization_id)
    |> Map.put_new(:started_at, DateTime.utc_now())
    |> Relationship.start_changeset()
    |> Repo.insert()
    |> case do
      {:ok, relationship} -> {:ok, normalize(relationship)}
      {:error, changeset} -> {:error, changeset}
    end
  end

  @impl true
  def finish(%{organization_id: organization_id}, id, ended_by_id) do
    case active_query(organization_id) |> where([r], r.id == ^id) |> Repo.one() do
      nil ->
        {:error, :not_found}

      relationship ->
        relationship
        |> Relationship.end_changeset(ended_by_id, DateTime.utc_now())
        |> Repo.update()
        |> case do
          {:ok, relationship} -> {:ok, normalize(relationship)}
          error -> error
        end
    end
  end

  @impl true
  def list(%{organization_id: organization_id}, filters) do
    organization_id
    |> active_query()
    |> filter(:coach_user_id, filters[:coach_user_id])
    |> filter(:client_user_id, filters[:client_user_id])
    |> order_by([r], desc: r.started_at)
    |> Repo.all()
    |> Enum.map(&normalize/1)
  end

  @impl true
  def active?(%{organization_id: organization_id}, coach_id, client_id) do
    organization_id
    |> active_query()
    |> where([r], r.coach_user_id == ^coach_id and r.client_user_id == ^client_id)
    |> Repo.exists?()
  end

  @impl true
  def client_ids(%{organization_id: organization_id}, coach_id) do
    organization_id
    |> active_query()
    |> where([r], r.coach_user_id == ^coach_id)
    |> select([r], r.client_user_id)
    |> Repo.all()
  end

  defp active_query(organization_id) do
    Relationship
    |> where([r], r.organization_id == ^organization_id and is_nil(r.ended_at))
  end

  defp filter(query, _field, nil), do: query
  defp filter(query, field, value), do: where(query, [r], field(r, ^field) == ^value)

  defp normalize(relationship) do
    Map.take(relationship, [
      :id,
      :coach_user_id,
      :client_user_id,
      :origin,
      :started_by_id,
      :started_at,
      :ended_at
    ])
  end
end
