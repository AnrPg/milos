defmodule MilosTraining.Infrastructure.Scaling.EctoScalingStore do
  @moduledoc "Ecto adapter of the scaling store (ADR-174). Every query names the gym explicitly."

  @behaviour MilosTraining.Scaling.Ports.ScalingStore

  import Ecto.Query

  alias MilosTraining.Repo
  alias MilosTraining.Scaling.ScalingSuggestion

  @max_list 200

  @impl true
  def get(%{organization_id: organization_id}, id) do
    case Ecto.UUID.cast(id) do
      {:ok, id} ->
        ScalingSuggestion
        |> where([s], s.organization_id == ^organization_id and s.id == ^id)
        |> Repo.one()

      :error ->
        nil
    end
  end

  @impl true
  def latest_live(%{organization_id: organization_id}, assignment_id, athlete_id) do
    ScalingSuggestion
    |> where(
      [s],
      s.organization_id == ^organization_id and s.assigned_workout_id == ^assignment_id and
        s.athlete_id == ^athlete_id and s.status != "superseded"
    )
    |> order_by([s], desc: s.inserted_at)
    |> limit(1)
    |> Repo.one()
  end

  @impl true
  def insert(%{organization_id: organization_id}, attrs) do
    attrs
    |> ScalingSuggestion.create_changeset()
    |> Ecto.Changeset.put_change(:organization_id, organization_id)
    |> Repo.insert()
  end

  @impl true
  def replace(context, %ScalingSuggestion{} = previous, attrs) do
    Repo.transaction(fn ->
      with {:ok, _old} <-
             previous
             |> ScalingSuggestion.update_changeset(%{status: "superseded"})
             |> Repo.update(),
           {:ok, inserted} <- insert(context, attrs) do
        inserted
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  @impl true
  def update(_context, %ScalingSuggestion{} = suggestion, changes) do
    suggestion |> ScalingSuggestion.update_changeset(changes) |> Repo.update()
  end

  @impl true
  def list(%{organization_id: organization_id}, filters) do
    ScalingSuggestion
    |> where([s], s.organization_id == ^organization_id)
    |> filter(filters)
    |> order_by([s], asc: s.scheduled_for, asc: s.inserted_at)
    |> limit(@max_list)
    |> Repo.all()
  end

  defp filter(query, filters) do
    Enum.reduce(filters, query, fn
      {:status, status}, query when is_binary(status) -> where(query, [s], s.status == ^status)
      {:athlete_ids, :all}, query -> query
      {:athlete_ids, ids}, query when is_list(ids) -> where(query, [s], s.athlete_id in ^ids)
      {:from, %Date{} = from}, query -> where(query, [s], s.scheduled_for >= ^from)
      _other, query -> query
    end)
  end

  @impl true
  def approved_for_member(%{organization_id: organization_id}, athlete_id, workout_id, from) do
    ScalingSuggestion
    |> where(
      [s],
      s.organization_id == ^organization_id and s.athlete_id == ^athlete_id and
        s.master_workout_id == ^workout_id and s.status == "approved" and s.scheduled_for >= ^from
    )
    |> order_by([s], asc: s.scheduled_for, desc: s.reviewed_at)
    |> limit(1)
    |> Repo.one()
  end

  @impl true
  def approved_history(%{organization_id: organization_id}, athlete_id, limit) do
    ScalingSuggestion
    |> where(
      [s],
      s.organization_id == ^organization_id and s.athlete_id == ^athlete_id and
        s.status == "approved"
    )
    |> order_by([s], desc: s.reviewed_at)
    |> limit(^limit)
    |> select([s], s.items)
    |> Repo.all()
    |> List.flatten()
    |> Enum.map(fn item ->
      %{
        movement: Map.get(item, "exercise_name"),
        change: Map.get(item, "change"),
        suggested: Map.get(item, "suggested")
      }
    end)
  end
end
