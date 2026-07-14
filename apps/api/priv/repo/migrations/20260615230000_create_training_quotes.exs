defmodule MilosTraining.Repo.Migrations.CreateTrainingQuotes do
  use Ecto.Migration

  def change do
    create table(:training_quotes, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :body, :text, null: false
      add :author, :string

      timestamps()
    end
  end
end
