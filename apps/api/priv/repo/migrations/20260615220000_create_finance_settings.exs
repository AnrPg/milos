defmodule MilosTraining.Repo.Migrations.CreateFinanceSettings do
  use Ecto.Migration

  def change do
    create table(:finance_settings, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :payment_reminder_interval_days, :integer, default: 7, null: false

      timestamps(type: :utc_datetime_usec)
    end
  end
end
