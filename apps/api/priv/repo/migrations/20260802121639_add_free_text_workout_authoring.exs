defmodule MilosTraining.Repo.Migrations.AddFreeTextWorkoutAuthoring do
  use Ecto.Migration

  def change do
    execute(
      "ALTER TABLE master_workouts DROP CONSTRAINT master_workouts_authoring_mode_check",
      """
      ALTER TABLE master_workouts
      ADD CONSTRAINT master_workouts_authoring_mode_check
      CHECK (authoring_mode IN ('structured', 'quick_text'))
      """
    )

    alter table(:master_workouts) do
      add :free_text_body, :text
      add :free_text_document, :map
    end

    create constraint(:master_workouts, :master_workouts_authoring_mode_check,
             check: "authoring_mode IN ('structured', 'quick_text', 'free_text')"
           )
  end
end
