defmodule MilosTraining.Infrastructure.Identity.EctoSavedFilterStore do
  @moduledoc "Ecto adapter of remembered filters (ADR-151)."

  @behaviour MilosTraining.Identity.Ports.SavedFilterStore

  import Ecto.Query

  alias MilosTraining.Identity.SavedFilter
  alias MilosTraining.Repo

  @impl true
  def list(%{user_id: user_id}, surface) do
    SavedFilter
    |> where([f], f.user_id == ^user_id and f.surface == ^surface)
    |> order_by([f], desc: f.last_used_at)
    |> Repo.all()
    |> Enum.map(&normalize/1)
  end

  @impl true
  def put_last_used(%{user_id: user_id}, surface, params, at) do
    upsert(
      %{
        user_id: user_id,
        surface: surface,
        kind: "last_used",
        name: nil,
        params: params,
        last_used_at: at
      },
      {:unsafe_fragment, ~s|("user_id","surface") WHERE kind = 'last_used'|}
    )
  end

  @impl true
  def put_named(%{user_id: user_id}, surface, name, params, at) do
    upsert(
      %{
        user_id: user_id,
        surface: surface,
        kind: "named",
        name: name,
        params: params,
        last_used_at: at
      },
      {:unsafe_fragment, ~s|("user_id","surface",lower("name")) WHERE kind = 'named'|}
    )
  end

  @impl true
  def count_named(%{user_id: user_id}, surface) do
    SavedFilter
    |> where([f], f.user_id == ^user_id and f.surface == ^surface and f.kind == "named")
    |> Repo.aggregate(:count)
  end

  @impl true
  def delete_named(%{user_id: user_id}, id) do
    with {:ok, id} <- Ecto.UUID.cast(id),
         {1, _} <-
           SavedFilter
           |> where([f], f.id == ^id and f.user_id == ^user_id and f.kind == "named")
           |> Repo.delete_all() do
      :ok
    else
      _missing -> {:error, :not_found}
    end
  end

  defp upsert(attrs, target) do
    now = DateTime.utc_now()

    %SavedFilter{}
    |> Ecto.Changeset.change(Map.merge(attrs, %{inserted_at: now, updated_at: now}))
    |> Repo.insert(
      on_conflict: {:replace, [:name, :params, :last_used_at, :updated_at]},
      conflict_target: target,
      returning: true
    )
    |> case do
      {:ok, filter} -> {:ok, normalize(filter)}
      {:error, changeset} -> {:error, changeset}
    end
  end

  @impl true
  def set_alert(%{user_id: user_id}, id, enabled, now) do
    changes =
      if enabled,
        do: [alert_enabled: true, alert_checked_at: now, alert_checked_on: nil, updated_at: now],
        else: [alert_enabled: false, updated_at: now]

    with {:ok, id} <- Ecto.UUID.cast(id),
         {1, [filter]} <-
           SavedFilter
           |> where([f], f.id == ^id and f.user_id == ^user_id and f.kind == "named")
           |> select([f], f)
           |> Repo.update_all(set: changes) do
      {:ok, normalize(filter)}
    else
      _missing -> {:error, :not_found}
    end
  end

  @impl true
  def alert_candidates(day, limit) do
    %{rows: rows} =
      Repo.query!("SELECT id, user_id FROM milos_around_alert_candidates($1, $2)", [day, limit])

    Enum.map(rows, fn [id, user_id] ->
      %{id: Ecto.UUID.load!(id), user_id: Ecto.UUID.load!(user_id)}
    end)
  end

  # Taking the day first means a retried or concurrent sweep finds it taken.
  @impl true
  def claim_alert(%{user_id: user_id}, id, day) do
    SavedFilter
    |> where([f], f.id == ^id and f.user_id == ^user_id and f.alert_enabled)
    |> where([f], is_nil(f.alert_checked_on) or f.alert_checked_on < ^day)
    |> select([f], f)
    |> Repo.update_all(set: [alert_checked_on: day])
    |> case do
      {1, [filter]} ->
        {:ok,
         %{
           id: filter.id,
           name: filter.name,
           params: filter.params,
           since: filter.alert_checked_at
         }}

      _taken ->
        {:error, :taken}
    end
  end

  @impl true
  def finish_alert(%{user_id: user_id}, id, at) do
    SavedFilter
    |> where([f], f.id == ^id and f.user_id == ^user_id)
    |> Repo.update_all(set: [alert_checked_at: at])

    :ok
  end

  defp normalize(%SavedFilter{} = f),
    do: %{
      id: f.id,
      kind: f.kind,
      name: f.name,
      params: f.params,
      last_used_at: f.last_used_at,
      alert: f.alert_enabled
    }
end
