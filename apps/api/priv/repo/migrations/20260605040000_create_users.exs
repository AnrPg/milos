defmodule MilosTraining.Repo.Migrations.CreateUsers do
  use Ecto.Migration

  def change do
    create table(:users, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :nickname, :string, null: false
      add :password_hash, :string, null: false
      add :role, :string, null: false, default: "member"
      add :leaderboard_opt_in, :boolean, null: false, default: false

      timestamps()
    end

    create unique_index(:users, [:nickname])
    create index(:users, [:role])
  end
end
