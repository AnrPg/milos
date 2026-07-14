defmodule MilosTraining.Repo.Migrations.CreateSchedulingAttendanceRecords do
  use Ecto.Migration

  def change do
    create table(:class_attendance_records, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :scheduled_class_id,
          references(:scheduled_classes, type: :binary_id, on_delete: :delete_all),
          null: false

      add :booking_id, references(:bookings, type: :binary_id, on_delete: :nilify_all)
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :status, :string, null: false, default: "attended"
      add :marked_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :marked_at, :utc_datetime_usec, null: false
      add :notes, :text
      add :params, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:class_attendance_records, [:scheduled_class_id, :user_id])
    create index(:class_attendance_records, [:user_id, :marked_at])
    create index(:class_attendance_records, [:status])

    create constraint(:class_attendance_records, :class_attendance_records_status_check,
             check: "status IN ('attended', 'missed', 'cancelled', 'late_cancel', 'no_show')"
           )
  end
end
