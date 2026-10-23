defmodule Palee.Repo.Migrations.AccountInterestsAndFirstRun do
  use Ecto.Migration

  # ADR-183.
  # - account_interests: what a person does (disciplines of the box
  #   vocabulary, a Partners level), one row per account. Personal: only its
  #   owner reads or writes it.
  # - users.completed_tours gains `first_run` for every existing account, so
  #   the first-run after sign-up greets new accounts only.

  @levels ~w(beginner intermediate advanced)

  def up do
    create table(:account_interests, primary_key: false) do
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all),
        primary_key: true

      add :disciplines, {:array, :string}, null: false, default: []
      add :level, :string

      timestamps(type: :utc_datetime_usec)
    end

    levels = Enum.map_join(@levels, ", ", &"'#{&1}'")

    create constraint(:account_interests, :account_interests_level_check,
             check: "level IS NULL OR level IN (#{levels})"
           )

    create constraint(:account_interests, :account_interests_disciplines_check,
             check: "cardinality(disciplines) <= 12"
           )

    owner = "user_id = NULLIF(current_setting('app.user_id', true), '')::uuid"

    execute("""
    CREATE POLICY account_interests_owner_policy ON account_interests
    FOR ALL USING (#{owner}) WITH CHECK (#{owner})
    """)

    execute("ALTER TABLE account_interests ENABLE ROW LEVEL SECURITY")
    execute("ALTER TABLE account_interests FORCE ROW LEVEL SECURITY")

    execute("""
    UPDATE users
    SET completed_tours = array_append(completed_tours, 'first_run')
    WHERE NOT ('first_run' = ANY(completed_tours))
    """)
  end

  def down do
    execute("UPDATE users SET completed_tours = array_remove(completed_tours, 'first_run')")
    drop table(:account_interests)
  end
end
