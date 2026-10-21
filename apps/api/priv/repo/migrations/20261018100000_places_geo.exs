defmodule Palee.Repo.Migrations.PlacesGeo do
  use Ecto.Migration

  # ADR-141: PostGIS, and where a gym location is. Coordinates are stored as
  # plain numbers so every reader (Ecto schemas, tenant export) decodes them
  # without a geometry type; distance search goes through
  # `palee_geo_point/2`, an immutable function that a GiST expression index
  # covers.

  def up do
    execute("CREATE EXTENSION IF NOT EXISTS postgis")

    # The body is a SQL-standard one (BEGIN ATOMIC): PostGIS names are bound
    # when the function is created, not looked up on every call. Since
    # PostgreSQL 17, CREATE INDEX, REINDEX, ANALYZE and VACUUM run index
    # expressions with search_path = pg_catalog, pg_temp, where a string body
    # cannot find `geography`. It stays inlinable (no SET clause).
    execute("""
    CREATE FUNCTION palee_geo_point(latitude double precision, longitude double precision)
    RETURNS geography
    LANGUAGE sql IMMUTABLE STRICT PARALLEL SAFE
    BEGIN ATOMIC
      SELECT ST_SetSRID(ST_MakePoint(longitude, latitude), 4326)::geography;
    END
    """)

    alter table(:facility_locations) do
      add :latitude, :float
      add :longitude, :float
      add :neighbourhood, :string
      add :city, :string
      add :country_code, :string, size: 2
      add :opening_hours, {:array, :map}, null: false, default: []
      add :accessibility, {:array, :string}, null: false, default: []
    end

    create constraint(:facility_locations, :facility_locations_coordinates_check,
             check: """
             (latitude IS NULL AND longitude IS NULL) OR
             (latitude BETWEEN -90 AND 90 AND longitude BETWEEN -180 AND 180)
             """
           )

    execute("""
    CREATE INDEX facility_locations_point_index ON facility_locations
    USING gist (palee_geo_point(latitude, longitude))
    WHERE latitude IS NOT NULL AND archived_at IS NULL
    """)
  end

  def down do
    execute("DROP INDEX IF EXISTS facility_locations_point_index")
    drop constraint(:facility_locations, :facility_locations_coordinates_check)

    alter table(:facility_locations) do
      remove :latitude
      remove :longitude
      remove :neighbourhood
      remove :city
      remove :country_code
      remove :opening_hours
      remove :accessibility
    end

    execute("DROP FUNCTION IF EXISTS palee_geo_point(double precision, double precision)")
  end
end
