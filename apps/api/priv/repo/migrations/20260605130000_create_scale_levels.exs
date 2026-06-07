defmodule MilosTraining.Repo.Migrations.CreateScaleLevels do
  use Ecto.Migration

  def change do
    create table(:scale_levels, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :slug, :string, null: false
      add :label, :string, null: false
      add :sort_order, :integer, null: false
      add :is_active, :boolean, null: false, default: true

      timestamps()
    end

    create unique_index(:scale_levels, [:slug])
    create unique_index(:scale_levels, [:sort_order], where: "is_active = true")
  end
end
