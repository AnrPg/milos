defmodule MilosTraining.Repo.Migrations.AddFreeTextWorkoutAuthoring do
  use Ecto.Migration

  def change do
    alter table(:master_workouts) do
      add :free_text_body, :text
      add :free_text_document, :map
    end
  end
end
