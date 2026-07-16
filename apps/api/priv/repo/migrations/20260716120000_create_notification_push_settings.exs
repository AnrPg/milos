defmodule MilosTraining.Repo.Migrations.CreateNotificationPushSettings do
  use Ecto.Migration

  def change do
    create table(:notification_push_settings, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :vapid_public_key, :text
      add :vapid_private_key, :text
      add :vapid_subject, :string

      timestamps(type: :utc_datetime_usec)
    end
  end
end
