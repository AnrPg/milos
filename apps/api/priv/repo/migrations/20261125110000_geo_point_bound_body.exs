defmodule MilosTraining.Repo.Migrations.GeoPointBoundBody do
  use Ecto.Migration

  # Databases migrated before 20261018100000 was corrected still have
  # `milos_geo_point/2` with a string body, which PostgreSQL 17+ cannot run
  # inside REINDEX, ANALYZE or VACUUM (restricted search_path). Same result,
  # SQL-standard body; on databases that already have it this is a no-op.

  def up do
    execute("""
    CREATE OR REPLACE FUNCTION milos_geo_point(latitude double precision, longitude double precision)
    RETURNS geography
    LANGUAGE sql IMMUTABLE STRICT PARALLEL SAFE
    BEGIN ATOMIC
      SELECT ST_SetSRID(ST_MakePoint(longitude, latitude), 4326)::geography;
    END
    """)
  end

  def down do
    :ok
  end
end
