defmodule MilosTraining.Infrastructure.Places.EctoGazetteerStore do
  @moduledoc "Ecto adapter of the neighbourhood gazetteer (ADR-154)."

  @behaviour MilosTraining.Places.Ports.GazetteerStore

  import Ecto.Query

  alias MilosTraining.Places.Neighbourhood
  alias MilosTraining.Repo

  @nearest_reach_m 5_000

  @impl true
  def search(query, limit) do
    pattern = "%" <> escape_like(query) <> "%"
    prefix = escape_like(query) <> "%"

    Neighbourhood
    |> where([n], like(n.search_key, ^pattern))
    |> order_by([n],
      asc: fragment("CASE WHEN ? LIKE ? THEN 0 ELSE 1 END", n.search_key, ^prefix),
      asc: fragment("CASE WHEN ? = 'city' THEN 0 ELSE 1 END", n.kind),
      asc: n.name
    )
    |> limit(^limit)
    |> Repo.all()
    |> Enum.map(&normalize/1)
  end

  @impl true
  def get_many([]), do: []

  def get_many(ids) do
    Neighbourhood
    |> where([n], n.id in ^ids)
    |> Repo.all()
    |> Enum.map(&normalize/1)
  end

  @impl true
  def nearest({latitude, longitude}) do
    Neighbourhood
    |> where([n], n.kind == "neighbourhood")
    |> where(
      [n],
      fragment(
        "ST_DWithin(milos_geo_point(?, ?), milos_geo_point(?::float8, ?::float8), ?)",
        n.latitude,
        n.longitude,
        ^latitude,
        ^longitude,
        @nearest_reach_m
      )
    )
    |> order_by([n],
      asc:
        fragment(
          "ST_Distance(milos_geo_point(?, ?), milos_geo_point(?::float8, ?::float8))",
          n.latitude,
          n.longitude,
          ^latitude,
          ^longitude
        )
    )
    |> limit(1)
    |> Repo.one()
    |> normalize()
  end

  defp normalize(nil), do: nil

  defp normalize(%Neighbourhood{} = n),
    do:
      Map.take(n, [
        :id,
        :slug,
        :kind,
        :name,
        :name_en,
        :city_slug,
        :latitude,
        :longitude,
        :radius_m
      ])

  defp escape_like(text), do: String.replace(text, ~r/([\\%_])/, "\\\\\\1")
end
