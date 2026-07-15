defmodule MilosTraining.Repo.Migrations.CreateAdminAthleteNotes do
  use Ecto.Migration

  def change do
    create table(:admin_athlete_notes, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :admin_id, references(:users, type: :binary_id, on_delete: :restrict), null: false
      add :athlete_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :body, :text, null: false

      timestamps(updated_at: false, type: :utc_datetime)
    end

    create index(:admin_athlete_notes, [:athlete_id, :inserted_at])
    create index(:admin_athlete_notes, [:admin_id, :inserted_at])
  end
end
