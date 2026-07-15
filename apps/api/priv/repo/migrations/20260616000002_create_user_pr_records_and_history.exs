defmodule MilosTraining.Repo.Migrations.CreateUserPrRecordsAndHistory do
  use Ecto.Migration

  def change do
    create table(:user_pr_records, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :name, :text, null: false
      add :current_score, :numeric, null: false
      add :unit, :string, null: false
      add :higher_is_better, :boolean, default: true, null: false
      add :beaten_on, :date, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create index(:user_pr_records, [:user_id])
    create index(:user_pr_records, [:user_id, :beaten_on])

    create table(:user_pr_history, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :pr_record_id, references(:user_pr_records, type: :binary_id, on_delete: :delete_all),
        null: false

      add :score, :numeric, null: false
      add :beaten_on, :date, null: false

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:user_pr_history, [:pr_record_id])
  end
end
