defmodule Palee.Repo.Migrations.CreateNotificationPreferences do
  @moduledoc """
  ADR-199: per-category notification choices (Εγώ › Ρυθμίσεις ›
  Ειδοποιήσεις). One row per person, category and channel, kept only when it
  was changed, so no row means today's behaviour (on). The categories are
  named in the domain, not here, so a new one needs no migration. Personal
  data: owner-only RLS.
  """

  use Ecto.Migration

  def change do
    create table(:notification_preferences, primary_key: false) do
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all),
        primary_key: true

      add :category, :string, primary_key: true
      add :channel, :string, primary_key: true
      add :enabled, :boolean, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create constraint(:notification_preferences, :notification_preferences_shape_check,
             check: "category ~ '^[a-z][a-z_]{1,31}$' AND channel IN ('in_app', 'push', 'email')"
           )

    execute(
      """
      CREATE POLICY notification_preferences_owner_policy ON notification_preferences
      USING (user_id = NULLIF(current_setting('app.user_id', true), '')::uuid)
      WITH CHECK (user_id = NULLIF(current_setting('app.user_id', true), '')::uuid)
      """,
      "DROP POLICY IF EXISTS notification_preferences_owner_policy ON notification_preferences"
    )

    execute(
      "ALTER TABLE notification_preferences ENABLE ROW LEVEL SECURITY",
      "ALTER TABLE notification_preferences DISABLE ROW LEVEL SECURITY"
    )

    execute(
      "ALTER TABLE notification_preferences FORCE ROW LEVEL SECURITY",
      "ALTER TABLE notification_preferences NO FORCE ROW LEVEL SECURITY"
    )
  end
end
