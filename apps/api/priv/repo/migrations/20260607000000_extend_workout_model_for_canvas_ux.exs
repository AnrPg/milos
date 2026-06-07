defmodule MilosTraining.Repo.Migrations.ExtendWorkoutModelForCanvasUx do
  use Ecto.Migration

  def up do
    alter table(:master_workouts) do
      add :status, :string, null: false, default: "draft"
      add :draft_data, :map
      modify :title, :string, null: true
      modify :type, :string, null: true
    end

    alter table(:workout_exercises) do
      remove :base_sets
      remove :base_reps
      remove :base_duration_seconds
      remove :description
      add :sets, :integer
      add :prescription_value, :integer
      add :prescription_unit, :string
      add :load_value, :integer
      add :load_mode, :string
      add :superset_group_id, :binary_id
      add :hr_zone, :integer
      add :tempo, :string
      add :rest_seconds, :integer
      add :cluster_rest_seconds, :integer
      add :rest_pause_seconds, :integer
      add :pacing, :integer
      add :interval_assignment, :integer
    end

    alter table(:exercise_variations) do
      remove :description
      remove :reps
      remove :duration_seconds
      add :exercise_name_override, :string
      add :prescription_value, :integer
      add :prescription_unit, :string
      add :load_value, :integer
      add :load_mode, :string
      add :excluded, :boolean, null: false, default: false
    end
  end

  def down do
    alter table(:exercise_variations) do
      remove :excluded
      remove :load_mode
      remove :load_value
      remove :prescription_unit
      remove :prescription_value
      remove :exercise_name_override
      add :duration_seconds, :integer
      add :reps, :integer
      add :description, :text
    end

    alter table(:workout_exercises) do
      remove :interval_assignment
      remove :pacing
      remove :rest_pause_seconds
      remove :cluster_rest_seconds
      remove :rest_seconds
      remove :tempo
      remove :hr_zone
      remove :superset_group_id
      remove :load_mode
      remove :load_value
      remove :prescription_unit
      remove :prescription_value
      remove :sets
      add :description, :text
      add :base_duration_seconds, :integer
      add :base_reps, :integer
      add :base_sets, :integer
    end

    alter table(:master_workouts) do
      modify :type, :string, null: false
      modify :title, :string, null: false
      remove :draft_data
      remove :status
    end
  end
end
