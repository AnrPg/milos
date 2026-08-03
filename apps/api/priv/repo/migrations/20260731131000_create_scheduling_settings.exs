defmodule MilosTraining.Repo.Migrations.CreateSchedulingSettings do
  use Ecto.Migration

  def change do
    create table(:scheduling_settings, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :default_capacity, :integer, null: false, default: 12
      add :default_auto_approve, :boolean, null: false, default: false
      add :default_booking_timeout_minutes, :integer, null: false, default: 60
      timestamps(type: :utc_datetime_usec)
    end
  end
end
