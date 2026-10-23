defmodule Palee.Repo.Migrations.WorldwideGazetteer do
  use Ecto.Migration

  # ADR-188: the gazetteer covers the whole world.
  # - Curated rows (the Greek seed of ADR-154) stay migration-only.
  # - A place picked from the OpenStreetMap geocoder is stored once as an
  #   `osm` row, keyed by its slug ("osm-r12345"), so «Η περιοχή μου»,
  #   filters and saved searches keep pointing at a row in this table. The
  #   application only writes what it signed in a search result itself.
  # - `context` / `context_en` tell same-named places apart ("Athens,
  #   Georgia" vs "Athens, Greece").
  # - A trigram index keeps the substring search fast as imported places
  #   accumulate.

  def up do
    alter table(:places_neighbourhoods) do
      add :source, :string, null: false, default: "curated"
      add :context, :string
      add :context_en, :string
    end

    create constraint(:places_neighbourhoods, :places_neighbourhoods_source_check,
             check: "source IN ('curated', 'osm')"
           )

    # Curated neighbourhoods are told apart by their city, cities by country.
    execute("""
    UPDATE places_neighbourhoods n
       SET context = c.name, context_en = c.name_en
      FROM places_neighbourhoods c
     WHERE n.kind = 'neighbourhood' AND c.kind = 'city' AND c.slug = n.city_slug
    """)

    execute("""
    UPDATE places_neighbourhoods
       SET context = 'Ελλάδα', context_en = 'Greece'
     WHERE kind = 'city' AND country_code = 'GR'
    """)

    execute("CREATE EXTENSION IF NOT EXISTS pg_trgm")

    execute("""
    CREATE INDEX places_neighbourhoods_search_key_trgm_index
    ON places_neighbourhoods USING gin (search_key gin_trgm_ops)
    """)

    # Sessions may add and refresh geocoded places, never curated ones.
    execute("""
    CREATE POLICY places_neighbourhoods_import_policy ON places_neighbourhoods
    FOR INSERT WITH CHECK (source = 'osm')
    """)

    execute("""
    CREATE POLICY places_neighbourhoods_refresh_policy ON places_neighbourhoods
    FOR UPDATE USING (source = 'osm') WITH CHECK (source = 'osm')
    """)
  end

  def down do
    execute("DROP POLICY places_neighbourhoods_refresh_policy ON places_neighbourhoods")
    execute("DROP POLICY places_neighbourhoods_import_policy ON places_neighbourhoods")
    execute("DROP INDEX places_neighbourhoods_search_key_trgm_index")

    # Home areas pointing at geocoded places go with them.
    execute("""
    DELETE FROM user_home_areas a
     USING places_neighbourhoods n
     WHERE n.id = a.neighbourhood_id AND n.source = 'osm'
    """)

    execute("DELETE FROM places_neighbourhoods WHERE source = 'osm'")
    drop constraint(:places_neighbourhoods, :places_neighbourhoods_source_check)

    alter table(:places_neighbourhoods) do
      remove :context_en
      remove :context
      remove :source
    end
  end
end
