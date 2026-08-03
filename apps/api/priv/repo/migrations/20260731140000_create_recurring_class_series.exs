defmodule MilosTraining.Repo.Migrations.CreateRecurringClassSeries do
  use Ecto.Migration

  def change do
    create table(:class_series, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :master_workout_id, references(:master_workouts, type: :binary_id), null: false
      add :class_type_id, references(:class_types, type: :binary_id), null: false
      add :name, :string, null: false
      add :duration_minutes, :integer, null: false
      add :timezone, :string, null: false, default: "Etc/UTC"
      add :starts_on, :date, null: false
      add :ends_on, :date
      add :local_start_time, :time, null: false
      add :weekdays, {:array, :integer}, null: false, default: []
      add :excluded_dates, {:array, :date}, null: false, default: []
      add :materialized_through, :date, null: false
      add :capacity, :integer, null: false
      add :auto_approve, :boolean, null: false, default: false
      add :booking_timeout_minutes, :integer, null: false, default: 60
      add :status, :string, null: false, default: "active"

      timestamps(type: :utc_datetime)
    end

    create constraint(:class_series, :class_series_duration_positive,
             check: "duration_minutes > 0 AND duration_minutes <= 1440"
           )

    create constraint(:class_series, :class_series_capacity_positive, check: "capacity > 0")

    create constraint(:class_series, :class_series_timeout_positive,
             check: "booking_timeout_minutes > 0"
           )

    create constraint(:class_series, :class_series_date_order,
             check: "ends_on IS NULL OR ends_on >= starts_on"
           )

    create constraint(:class_series, :class_series_weekdays_valid,
             check: "cardinality(weekdays) > 0 AND weekdays <@ ARRAY[1,2,3,4,5,6,7]::integer[]"
           )

    create constraint(:class_series, :class_series_status_valid,
             check: "status IN ('active', 'ended', 'cancelled')"
           )

    create index(:class_series, [:class_type_id])
    create index(:class_series, [:master_workout_id])
    create index(:class_series, [:starts_on, :ends_on])

    alter table(:scheduled_classes) do
      add :class_series_id,
          references(:class_series, type: :binary_id, on_delete: :nilify_all)

      add :name, :string, null: false, default: "Class"
      add :duration_minutes, :integer, null: false, default: 60
    end

    create constraint(:scheduled_classes, :scheduled_classes_duration_positive,
             check: "duration_minutes > 0 AND duration_minutes <= 1440"
           )

    create index(:scheduled_classes, [:class_series_id])

    create unique_index(:scheduled_classes, [:class_series_id, :scheduled_at],
             where: "class_series_id IS NOT NULL",
             name: :scheduled_classes_series_occurrence_unique
           )
  end
end
