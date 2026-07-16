defmodule MilosTraining.Repo.Migrations.AddUserSecurityVersion do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :security_version, :integer, null: false, default: 1
    end
  end
end
