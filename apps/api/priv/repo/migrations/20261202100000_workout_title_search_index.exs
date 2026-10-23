defmodule Palee.Repo.Migrations.WorkoutTitleSearchIndex do
  @moduledoc """
  The class form's WOD picker searches title words with ILIKE '%word%' in
  libraries of thousands; a trigram index keeps that an index scan.
  """
  use Ecto.Migration

  def up do
    execute("CREATE EXTENSION IF NOT EXISTS pg_trgm")

    execute("""
    CREATE INDEX IF NOT EXISTS master_workouts_title_trgm_index
    ON master_workouts USING gin (title gin_trgm_ops)
    """)

    create_if_not_exists index(:master_workouts, [:organization_id, :status, :updated_at])
  end

  def down do
    drop_if_exists index(:master_workouts, [:organization_id, :status, :updated_at])
    execute("DROP INDEX IF EXISTS master_workouts_title_trgm_index")
  end
end
