defmodule MilosTraining.Repo.Migrations.RetainWorkoutDslAuthoringState do
  use Ecto.Migration

  def change do
    alter table(:master_workouts) do
      add :authoring_mode, :string, null: false, default: "structured"
      add :dsl_version, :integer
      add :dsl_source, :text
      add :dsl_document, :map
      add :dsl_source_revision, :integer, null: false, default: 0
      add :last_dsl_diagnostics, {:array, :map}, null: false, default: []
    end

    create constraint(:master_workouts, :master_workouts_authoring_mode_check,
             check: "authoring_mode IN ('structured', 'quick_text')"
           )

    create constraint(:master_workouts, :master_workouts_dsl_version_check,
             check: "dsl_version IS NULL OR dsl_version = 1"
           )

    create constraint(:master_workouts, :master_workouts_dsl_source_revision_check,
             check: "dsl_source_revision >= 0"
           )

    create constraint(:master_workouts, :master_workouts_dsl_source_size_check,
             check: "dsl_source IS NULL OR octet_length(dsl_source) <= 200000"
           )
  end
end
