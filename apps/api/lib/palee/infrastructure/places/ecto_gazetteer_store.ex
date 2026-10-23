defmodule Palee.Infrastructure.Places.EctoGazetteerStore do
  @moduledoc "Ecto adapter of the neighbourhood gazetteer (ADR-154, ADR-188)."

  @behaviour Palee.Places.Ports.GazetteerStore

  import Ecto.Query

  alias Palee.Places.Neighbourhood
  alias Palee.Repo

  @nearest_reach_m 5_000

  # Refreshed on a repeat import: what the source says may have improved.
  @refreshed [
    :name,
    :name_en,
    :context,
    :context_en,
    :latitude,
    :longitude,
    :radius_m,
    :search_key,
    :name_key,
    :updated_at
  ]

  @impl true
  def search(query, limit) do
    pattern = "%" <> escape_like(query) <> "%"

    Neighbourhood
    |> where([n], like(n.search_key, ^pattern) or fragment("? <% ?", ^query, n.search_key))
    |> order_by([n],
      asc:
        fragment(
          "CASE WHEN position(? in ?) > 0 THEN 0 WHEN position(? in ?) > 0 THEN 1 WHEN ? LIKE ? THEN 2 ELSE 3 END",
          ^(" " <> query),
          fragment("' ' || coalesce(?, '')", n.name_key),
          ^(" " <> query),
          fragment("' ' || ?", n.search_key),
          n.search_key,
          ^pattern
        ),
      # Hand-picked places first (the app's home market), then bigger ones.
      asc: fragment("CASE WHEN ? = 'curated' THEN 0 ELSE 1 END", n.source),
      desc:
        fragment(
          "COALESCE(?, CASE WHEN ? = 'city' THEN 100000 ELSE 20000 END)",
          n.population,
          n.kind
        ),
      desc: fragment("word_similarity(?, ?)", ^query, n.search_key),
      asc: n.name
    )
    |> limit(^limit)
    |> Repo.all()
    |> Enum.map(&normalize/1)
  end

  @upsert_batch 2_000

  @impl true
  def upsert_many(source, places) do
    now = DateTime.utc_now()

    places
    |> Stream.map(fn place ->
      place
      |> Map.take([
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
        :population,
        :search_key,
        :name_key
      ])
      |> Map.merge(%{source: source, inserted_at: now, updated_at: now})
    end)
    |> Stream.chunk_every(@upsert_batch)
    |> Enum.reduce(0, fn rows, count ->
      {inserted, _rows} =
        Repo.insert_all(Neighbourhood, rows,
          on_conflict: {:replace, @refreshed ++ [:population, :kind]},
          conflict_target: :slug
        )

      count + inserted
    end)
  end

  @impl true
  def refreshed_at(source) do
    Neighbourhood
    |> where([n], n.source == ^source)
    |> select([n], max(n.updated_at))
    |> Repo.one()
  end

  @impl true
  def list_source(source) do
    Neighbourhood
    |> where([n], n.source == ^source)
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
          :search_key,
          :name_key
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
        :radius_m,
        :population,
        :country_code
      ])

  defp escape_like(text), do: String.replace(text, ~r/([\\%_])/, "\\\\\\1")
end
