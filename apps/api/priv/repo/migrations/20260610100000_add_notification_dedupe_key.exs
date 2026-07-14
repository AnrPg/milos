defmodule MilosTraining.Repo.Migrations.AddNotificationDedupeKey do
  use Ecto.Migration

  def up do
    alter table(:notifications) do
      add :dedupe_key, :text
    end

    execute("""
    UPDATE notifications
    SET dedupe_key = CONCAT('booking:', user_id, ':', type, ':', payload->>'booking_id')
    WHERE payload ? 'booking_id' AND dedupe_key IS NULL
    """)

    create unique_index(:notifications, [:user_id, :dedupe_key],
             where: "dedupe_key IS NOT NULL",
             name: :notifications_user_id_dedupe_key_index
           )
  end

  def down do
    drop_if_exists index(:notifications, [:user_id, :dedupe_key],
                     where: "dedupe_key IS NOT NULL",
                     name: :notifications_user_id_dedupe_key_index
                   )

    alter table(:notifications) do
      remove :dedupe_key
    end
  end
end
