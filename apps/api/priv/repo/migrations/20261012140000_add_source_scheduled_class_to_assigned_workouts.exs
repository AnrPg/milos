defmodule MilosTraining.Repo.Migrations.AddSourceScheduledClassToAssignedWorkouts do
  @moduledoc """
  ADR-107: personalized member programming.

  A nullable `source_scheduled_class_id` marks an assignment as a per-member
  variant of a class occurrence. It is a loose reference to the
  Scheduling-owned `scheduled_classes` row (no cross-context foreign key, like
  ADR-100's `source_reference_id`), so a variant survives slot deletion as a
  personal assignment. The column is additive on the already tenant-scoped,
  RLS-forced `assigned_workouts` table; the index serves the per-slot variant
  lookups made by the schedule calendar.
  """
  use Ecto.Migration

  def change do
    alter table(:assigned_workouts) do
      add :source_scheduled_class_id, :uuid
    end

    create index(:assigned_workouts, [:organization_id, :source_scheduled_class_id],
             where: "source_scheduled_class_id IS NOT NULL",
             name: :assigned_workouts_source_scheduled_class_index
           )
  end
end
