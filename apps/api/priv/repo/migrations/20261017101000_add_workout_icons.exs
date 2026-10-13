defmodule MilosTraining.Repo.Migrations.AddWorkoutIcons do
  use Ecto.Migration

  # `icon` is an emoji shown for the workout in the library. `icon_source`
  # records who chose it: "ai" (suggested after publishing) or "coach" (set by
  # hand, never overwritten). No icon means the library's keyword rules apply.
  def change do
    alter table(:master_workouts) do
      add :icon, :string, size: 32
      add :icon_source, :string, size: 16
    end
  end
end
