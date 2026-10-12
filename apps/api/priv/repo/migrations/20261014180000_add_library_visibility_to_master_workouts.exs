defmodule MilosTraining.Repo.Migrations.AddLibraryVisibilityToMasterWorkouts do
  use Ecto.Migration

  # ADR-115 (owner decision): workouts copied for a member's personalized
  # programming stay out of the shared workout library. Additive; existing
  # workouts keep `shared`.
  def change do
    alter table(:master_workouts) do
      add :library_visibility, :string, null: false, default: "shared"
    end

    create constraint(:master_workouts, :master_workouts_library_visibility_check,
             check: "library_visibility IN ('shared', 'personal')"
           )
  end
end
