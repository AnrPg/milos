defmodule MilosTraining.Infrastructure.Places.EctoHomeAreaStore do
  @moduledoc "Ecto adapter of «Η περιοχή μου» (ADR-154)."

  @behaviour MilosTraining.Places.Ports.HomeAreaStore

  import Ecto.Query

  alias MilosTraining.Places.{HomeArea, Neighbourhood}
  alias MilosTraining.Repo

  @impl true
  def list(%{user_id: user_id}) do
    HomeArea
    |> join(:inner, [a], n in Neighbourhood, on: n.id == a.neighbourhood_id)
    |> where([a], a.user_id == ^user_id)
    |> order_by([a], asc: a.position)
    |> select([_a, n], %{
      id: n.id,
      slug: n.slug,
      kind: n.kind,
      name: n.name,
      name_en: n.name_en,
      city_slug: n.city_slug,
      latitude: n.latitude,
      longitude: n.longitude,
      radius_m: n.radius_m
    })
    |> Repo.all()
  end

  @impl true
  def replace(%{user_id: user_id}, ids, now) do
    rows =
      ids
      |> Enum.with_index()
      |> Enum.map(fn {id, position} ->
        %{
          id: Ecto.UUID.generate(),
          user_id: user_id,
          neighbourhood_id: id,
          position: position,
          inserted_at: now,
          updated_at: now
        }
      end)

    Repo.transaction(fn ->
      HomeArea |> where([a], a.user_id == ^user_id) |> Repo.delete_all()
      Repo.insert_all(HomeArea, rows)
    end)
    |> case do
      {:ok, _result} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
end
