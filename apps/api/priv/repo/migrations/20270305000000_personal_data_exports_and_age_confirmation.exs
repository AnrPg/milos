defmodule Palee.Repo.Migrations.PersonalDataExportsAndAgeConfirmation do
  @moduledoc """
  ADR-267: "Download my data" and the minimum age at sign-up.

    * `personal_data_exports` – one row per request of a profile for a copy
      of its own data (GDPR articles 15 and 20). Built in the background in
      the person's own session, stored privately under the person's storage
      prefix and offered through short-lived links until `expires_at`. A
      personal table: the owner policy admits only the profile itself
      (`app.user_id`), forced, like `journal_exports`.
    * `logins.age_confirmed_at` – when the person confirmed at sign-up that
      they are at least the minimum age (16). Empty for logins created
      before this rule, for demo people and for profiles held by an import.
  """

  use Ecto.Migration

  @acting_user "NULLIF(current_setting('app.user_id', true), '')::uuid"

  def up do
    create table(:personal_data_exports, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :status, :string, null: false, default: "pending"
      add :record_count, :integer
      add :file, :map
      add :error, :string, size: 500
      add :requested_at, :utc_datetime_usec, null: false
      add :completed_at, :utc_datetime_usec
      add :expires_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create index(:personal_data_exports, [:user_id, :requested_at])

    # One request in progress per profile, even when two arrive together.
    create unique_index(:personal_data_exports, [:user_id],
             where: "status = 'pending'",
             name: :personal_data_exports_one_pending_index
           )

    create constraint(:personal_data_exports, :personal_data_exports_check,
             check: """
             status IN ('pending', 'ready', 'failed')
             AND (status <> 'ready' OR (file IS NOT NULL AND expires_at IS NOT NULL))
             """
           )

    execute("""
    CREATE POLICY personal_data_exports_owner_policy ON personal_data_exports
    USING (user_id = #{@acting_user})
    WITH CHECK (user_id = #{@acting_user})
    """)

    execute("ALTER TABLE personal_data_exports ENABLE ROW LEVEL SECURITY")
    execute("ALTER TABLE personal_data_exports FORCE ROW LEVEL SECURITY")

    alter table(:logins) do
      add :age_confirmed_at, :utc_datetime_usec
    end
  end

  def down do
    alter table(:logins) do
      remove :age_confirmed_at
    end

    drop table(:personal_data_exports)
  end
end
