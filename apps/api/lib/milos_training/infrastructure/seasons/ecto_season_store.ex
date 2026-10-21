defmodule MilosTraining.Infrastructure.Seasons.EctoSeasonStore do
  @moduledoc "Ecto adapter of season offerings and enrollments (ADR-167)."

  @behaviour MilosTraining.Seasons.Ports.SeasonStore

  import Ecto.Query

  alias MilosTraining.Repo
  alias MilosTraining.Seasons.{SeasonEnrollment, SeasonOffering}

  @impl true
  def create_offering(%{organization_id: organization_id}, attrs) do
    attrs
    |> Map.put(:organization_id, organization_id)
    |> SeasonOffering.create_changeset()
    |> Repo.insert()
  end

  @impl true
  def update_offering(_context, offering, attrs),
    do: offering |> SeasonOffering.update_changeset(attrs) |> Repo.update()

  @impl true
  def get_offering(%{organization_id: organization_id}, id) do
    with {:ok, id} <- Ecto.UUID.cast(id) do
      Repo.one(
        from o in SeasonOffering, where: o.id == ^id and o.organization_id == ^organization_id
      )
    else
      :error -> nil
    end
  end

  @impl true
  def list_offerings(%{organization_id: organization_id}, filters) do
    SeasonOffering
    |> where([o], o.organization_id == ^organization_id)
    |> statuses(Map.get(filters, :statuses))
    |> order_by([o], desc: o.starts_on, desc: o.inserted_at)
    |> limit(200)
    |> Repo.all()
  end

  @impl true
  def enrollment_counts(_context, []), do: %{}

  def enrollment_counts(%{organization_id: organization_id}, ids) do
    from(e in SeasonEnrollment,
      where: e.organization_id == ^organization_id and e.season_offering_id in ^ids,
      group_by: [e.season_offering_id, e.status],
      select: {e.season_offering_id, e.status, count(e.id)}
    )
    |> Repo.all()
    |> Enum.reduce(%{}, fn {offering_id, status, count}, acc ->
      Map.update(acc, offering_id, %{status => count}, &Map.put(&1, status, count))
    end)
  end

  @impl true
  def titles(_context, []), do: %{}

  def titles(%{organization_id: organization_id}, ids) do
    from(o in SeasonOffering,
      where: o.organization_id == ^organization_id and o.id in ^ids,
      select: {o.id, o.title}
    )
    |> Repo.all()
    |> Map.new()
  end

  @impl true
  def get_enrollment(%{organization_id: organization_id}, id) do
    with {:ok, id} <- Ecto.UUID.cast(id) do
      Repo.one(
        from e in SeasonEnrollment, where: e.id == ^id and e.organization_id == ^organization_id
      )
    else
      :error -> nil
    end
  end

  @impl true
  def get_member_enrollment(%{organization_id: organization_id}, offering_id, user_id) do
    Repo.one(
      from e in SeasonEnrollment,
        where:
          e.organization_id == ^organization_id and e.season_offering_id == ^offering_id and
            e.user_id == ^user_id
    )
  end

  @impl true
  def list_enrollments(%{organization_id: organization_id}, offering_id) do
    from(e in SeasonEnrollment,
      where: e.organization_id == ^organization_id and e.season_offering_id == ^offering_id,
      order_by: [asc: e.requested_at, asc: e.inserted_at]
    )
    |> Repo.all()
  end

  @impl true
  def list_member_enrollments(%{organization_id: organization_id}, user_id) do
    from(e in SeasonEnrollment,
      where: e.organization_id == ^organization_id and e.user_id == ^user_id
    )
    |> Repo.all()
  end

  @impl true
  def insert_enrollment(%{organization_id: organization_id}, attrs) do
    attrs
    |> Map.put(:organization_id, organization_id)
    |> SeasonEnrollment.create_changeset()
    |> Repo.insert()
  end

  @impl true
  def update_enrollment(_context, enrollment, changes),
    do: enrollment |> SeasonEnrollment.transition_changeset(changes) |> Repo.update()

  @impl true
  def first_waitlisted(%{organization_id: organization_id}, offering_id) do
    from(e in SeasonEnrollment,
      where:
        e.organization_id == ^organization_id and e.season_offering_id == ^offering_id and
          e.status == "waitlisted",
      order_by: [asc: e.requested_at, asc: e.inserted_at],
      limit: 1
    )
    |> Repo.one()
  end

  @impl true
  def with_offering_lock(_context, offering_id, fun) do
    Repo.transaction(fn ->
      Repo.query!("SELECT pg_advisory_xact_lock(hashtextextended($1, 167))", [
        "season:" <> offering_id
      ])

      case fun.() do
        {:error, reason} -> Repo.rollback(reason)
        result -> result
      end
    end)
    |> case do
      {:ok, result} -> result
      {:error, reason} -> {:error, reason}
    end
  end

  defp statuses(query, nil), do: query
  defp statuses(query, list), do: where(query, [o], o.status in ^list)
end
