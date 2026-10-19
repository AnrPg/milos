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

  defp normalize(%SavedFilter{} = f),
    do: %{id: f.id, kind: f.kind, name: f.name, params: f.params, last_used_at: f.last_used_at}
end
