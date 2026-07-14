defmodule MilosTraining.Repo.Migrations.CreatePushSubscriptionsAndExpandNotificationTypes do
  use Ecto.Migration

  def up do
    create table(:push_subscriptions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :endpoint, :text, null: false
      add :p256dh_key, :text, null: false
      add :auth_key, :text, null: false
      add :expiration_time, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:push_subscriptions, [:user_id])

    create unique_index(:push_subscriptions, [:endpoint],
             name: :push_subscriptions_endpoint_index
           )

    drop constraint(:notifications, :notifications_type_check)

    create constraint(:notifications, :notifications_type_check,
             check:
               "type IN ('booking_approved', 'booking_rejected', 'booking_pending', 'booking_timeout', 'workout_note', 'workout_completed', 'admin_note', 'challenge_completed')"
           )
  end

  def down do
    drop constraint(:notifications, :notifications_type_check)

    create constraint(:notifications, :notifications_type_check,
             check:
               "type IN ('booking_approved', 'booking_rejected', 'booking_pending', 'booking_timeout', 'workout_note', 'workout_completed', 'admin_note')"
           )

    drop_if_exists unique_index(:push_subscriptions, [:endpoint],
                     name: :push_subscriptions_endpoint_index
                   )

    drop_if_exists index(:push_subscriptions, [:user_id])
    drop table(:push_subscriptions)
  end
end
