defmodule MilosTraining.Repo.Migrations.CreateSchedulingTables do
  use Ecto.Migration

  def change do
    create table(:scheduled_classes, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :master_workout_id,
          references(:master_workouts, type: :binary_id, on_delete: :restrict),
          null: false

      add :training_type, :string, null: false
      add :scheduled_at, :utc_datetime, null: false
      add :capacity, :integer, null: false
      add :auto_approve, :boolean, null: false, default: false
      add :booking_timeout_minutes, :integer, null: false, default: 60

      timestamps(type: :utc_datetime)
    end

    create index(:scheduled_classes, [:scheduled_at])
    create index(:scheduled_classes, [:training_type])

    create constraint(:scheduled_classes, :scheduled_classes_training_type_check,
             check:
               "training_type IN ('crossfit', 'strength', 'gymnastics', 'aerobics', 'flexibility', 'recovery')"
           )

    create constraint(:scheduled_classes, :scheduled_classes_capacity_check,
             check: "capacity > 0"
           )

    create constraint(:scheduled_classes, :scheduled_classes_timeout_minutes_check,
             check: "booking_timeout_minutes > 0"
           )

    create table(:bookings, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :scheduled_class_id,
          references(:scheduled_classes, type: :binary_id, on_delete: :delete_all),
          null: false

      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :status, :string, null: false
      add :admin_message, :text
      add :timeout_job_id, :bigint

      timestamps(type: :utc_datetime)
    end

    create index(:bookings, [:scheduled_class_id])
    create index(:bookings, [:user_id])
    create index(:bookings, [:status])

    create unique_index(:bookings, [:scheduled_class_id, :user_id],
             name: :bookings_slot_user_index
           )

    create constraint(:bookings, :bookings_status_check,
             check: "status IN ('pending', 'approved', 'rejected', 'cancelled')"
           )
  end
end
