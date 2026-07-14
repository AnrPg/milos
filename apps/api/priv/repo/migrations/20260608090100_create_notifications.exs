defmodule MilosTraining.Repo.Migrations.CreateNotifications do
  use Ecto.Migration

  def change do
    create table(:notifications, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :type, :string, null: false
      add :payload, :map, null: false, default: %{}
      add :read_at, :utc_datetime

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:notifications, [:user_id, :read_at])
    create index(:notifications, [:user_id, :inserted_at])

    create constraint(:notifications, :notifications_type_check,
             check:
               "type IN ('booking_approved', 'booking_rejected', 'booking_pending', 'booking_timeout', 'workout_note', 'admin_note')"
           )
  end
end
