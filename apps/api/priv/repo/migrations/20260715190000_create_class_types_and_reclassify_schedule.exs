defmodule MilosTraining.Repo.Migrations.CreateClassTypesAndReclassifySchedule do
  use Ecto.Migration

  def change do
    create table(:class_types, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :slug, :string, null: false
      add :sort_order, :integer, null: false, default: 0
      add :archived_at, :utc_datetime
      timestamps(type: :utc_datetime)
    end

    create unique_index(:class_types, [:slug])
    create index(:class_types, [:archived_at, :sort_order])
    create constraint(:class_types, :class_types_name_not_blank, check: "btrim(name) <> ''")
    create constraint(:class_types, :class_types_slug_not_blank, check: "btrim(slug) <> ''")

    execute(
      """
      INSERT INTO class_types (id, name, slug, sort_order, inserted_at, updated_at)
      VALUES
        ('00000000-0000-0000-0000-00000000c001', 'CrossFit', 'crossfit', 10, NOW(), NOW()),
        ('00000000-0000-0000-0000-00000000c002', 'Strength', 'strength', 20, NOW(), NOW()),
        ('00000000-0000-0000-0000-00000000c003', 'Gymnastics', 'gymnastics', 30, NOW(), NOW()),
        ('00000000-0000-0000-0000-00000000c004', 'Aerobics', 'aerobics', 40, NOW(), NOW()),
        ('00000000-0000-0000-0000-00000000c005', 'Flexibility', 'flexibility', 50, NOW(), NOW()),
        ('00000000-0000-0000-0000-00000000c006', 'Recovery', 'recovery', 60, NOW(), NOW())
      """,
      "DELETE FROM class_types"
    )

    drop constraint(:scheduled_classes, :scheduled_classes_training_type_check)

    alter table(:scheduled_classes) do
      remove :training_type, :string

      add :class_type_id,
          references(:class_types, type: :binary_id, on_delete: :restrict),
          null: false
    end

    create index(:scheduled_classes, [:class_type_id])
  end
end
