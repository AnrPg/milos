defmodule Palee.Infrastructure.Places.EctoGazetteerStore do
  @moduledoc "Ecto adapter of the neighbourhood gazetteer (ADR-154, ADR-188)."

  @behaviour Palee.Places.Ports.GazetteerStore

  import Ecto.Query

  alias Palee.Places.Neighbourhood
  alias Palee.Repo

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
        "ST_DWithin(palee_geo_point(?, ?), palee_geo_point(?::float8, ?::float8), ?)",
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
          "ST_Distance(palee_geo_point(?, ?), palee_geo_point(?::float8, ?::float8))",
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

  # Refreshed on a repeat import: what the geocoder says may have improved.
  @refreshed [
    :name,
    :name_en,
    :context,
    :context_en,
    :latitude,
    :longitude,
    :radius_m,
    :search_key,
    :updated_at
  ]

  @impl true
  def import(place) do
    row =
      %Neighbourhood{source: "osm"}
      |> Ecto.Changeset.change(
        Map.take(place, [
          :id,
          :slug,
          :kind,
          :name,
          :name_en,
          :context,
          :context_en,
          :country_code,
          :latitude,
          :longitude,
          :radius_m,
          :search_key
        ])
      )

    case Repo.insert(row,
           on_conflict: {:replace, @refreshed},
           conflict_target: :slug,
           returning: true
         ) do
      {:ok, stored} -> {:ok, normalize(stored)}
      {:error, changeset} -> {:error, changeset}
    end
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
        :context,
        :context_en,
        :latitude,
        :longitude,
        :radius_m
      ])

  defp escape_like(text), do: String.replace(text, ~r/([\\%_])/, "\\\\\\1")
end
