defmodule MilosTraining.Repo.Migrations.ClassTypeLevelAudiences do
  use Ecto.Migration

  # Phase 2 Πρόγραμμα filters «Επίπεδο» and «Κοινό»: the gym tags each class
  # type. An empty audience list means the class is open to everyone.
  def change do
    alter table(:class_types) do
      add :level, :text, null: false, default: "all_levels"
      add :audiences, {:array, :text}, null: false, default: []
    end

    create constraint(:class_types, :class_types_level_check,
             check: "level IN ('beginner', 'all_levels', 'advanced')"
           )

    create constraint(:class_types, :class_types_audiences_check,
             check:
               "audiences <@ ARRAY['women', 'teens', 'kids', 'over_40', 'seniors', 'prenatal', 'adaptive']::text[]"
           )
  end
end
