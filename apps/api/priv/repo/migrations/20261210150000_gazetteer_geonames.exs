defmodule Palee.Repo.Migrations.GazetteerGeonames do
  use Ecto.Migration

  # ADR-188 (amended): every town of 500+ people worldwide comes from
  # GeoNames (CC BY 4.0) into the gazetteer, refreshed by a background job,
  # so most searches never leave our database. `population` ranks
  # namesakes ("Athens": Greece before Ohio). The job writes `geonames`
  # rows; curated rows stay migration-only. `name_key` (the place's own
  # names, folded like the search key) ranks "Athens" the city above
  # neighbourhoods of Athens.

  import Ecto.Query

  def up do
    alter table(:places_neighbourhoods) do
      add :population, :integer
      add :name_key, :text
    end

    flush()
    backfill_name_keys()

    drop constraint(:places_neighbourhoods, :places_neighbourhoods_source_check)

    create constraint(:places_neighbourhoods, :places_neighbourhoods_source_check,
             check: "source IN ('curated', 'osm', 'geonames')"
           )

    execute("DROP POLICY places_neighbourhoods_import_policy ON places_neighbourhoods")
    execute("DROP POLICY places_neighbourhoods_refresh_policy ON places_neighbourhoods")

    execute("""
    CREATE POLICY places_neighbourhoods_import_policy ON places_neighbourhoods
    FOR INSERT WITH CHECK (source IN ('osm', 'geonames'))
    """)

    execute("""
    CREATE POLICY places_neighbourhoods_refresh_policy ON places_neighbourhoods
    FOR UPDATE USING (source IN ('osm', 'geonames')) WITH CHECK (source IN ('osm', 'geonames'))
    """)

    create index(:places_neighbourhoods, [:source, :updated_at])
  end

  def down do
    drop index(:places_neighbourhoods, [:source, :updated_at])
    execute("DROP POLICY places_neighbourhoods_refresh_policy ON places_neighbourhoods")
    execute("DROP POLICY places_neighbourhoods_import_policy ON places_neighbourhoods")

    execute("""
    CREATE POLICY places_neighbourhoods_import_policy ON places_neighbourhoods
    FOR INSERT WITH CHECK (source = 'osm')
    """)

    execute("""
    CREATE POLICY places_neighbourhoods_refresh_policy ON places_neighbourhoods
    FOR UPDATE USING (source = 'osm') WITH CHECK (source = 'osm')
    """)

    execute("""
    DELETE FROM user_home_areas a
     USING places_neighbourhoods n
     WHERE n.id = a.neighbourhood_id AND n.source = 'geonames'
    """)

    execute("DELETE FROM places_neighbourhoods WHERE source = 'geonames'")
    drop constraint(:places_neighbourhoods, :places_neighbourhoods_source_check)

    create constraint(:places_neighbourhoods, :places_neighbourhoods_source_check,
             check: "source IN ('curated', 'osm')"
           )

    alter table(:places_neighbourhoods) do
      remove :name_key
      remove :population
    end
  end

  defp backfill_name_keys do
    rows =
      repo().all(
        from(n in "places_neighbourhoods", select: {type(n.id, :binary_id), n.name, n.name_en})
      )

    for {id, name, name_en} <- rows do
      repo().update_all(
        from(n in "places_neighbourhoods", where: n.id == type(^id, :binary_id)),
        set: [name_key: name_key(name, name_en)]
      )
    end
  end

  # Same folding as Palee.Places.Domain.SearchKey, frozen here.
  defp name_key(name, name_en) do
    [name, name_en]
    |> Enum.map(fn text ->
      text
      |> String.normalize(:nfd)
      |> String.replace(~r/\p{Mn}/u, "")
      |> String.downcase()
      |> String.replace("ς", "σ")
      |> String.split()
      |> Enum.join(" ")
    end)
    |> Enum.uniq()
    |> Enum.join(" ")
  end
end
