defmodule Palee.Repo.Migrations.LoginsAndProfiles do
  @moduledoc """
  ADR-187: one login per email holding up to three profiles.

  - `logins` owns the credentials: the email (unique, case-insensitive), the
    password hash and a security version that revokes every profile's
    sessions at once (password change, reset).
  - `users` stay the profiles (every foreign key in the schema keeps pointing
    at them) and gain `login_id`. Today every account has a unique email, so
    each existing user gets its own login, 1:1, and nobody's sign-in changes.
  - `users.nickname` (already the normalized unique name) is the profile's
    @handle and `display_nickname` its free, non-unique display name. The
    columns keep their names because SQL functions and views reference them;
    the Ecto schema maps them to `handle` and `display_name`.
  - `search_text` is the hidden folded search key (Elixir keeps it current);
    existing rows get `lower(display_name) || handle`, which already covers
    the transliterated form because handles were stored transliterated.
  - `handle_reservations` keeps a renamed handle for its former owner for
    30 days.
  - A trigger caps profiles per login at three as a backstop to the locked
    check in the application.
  """
  use Ecto.Migration

  def up do
    execute("CREATE EXTENSION IF NOT EXISTS pg_trgm")

    create table(:logins, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :email, :string, null: false
      add :password_hash, :string, null: false
      # Starts at 0 so a token's "sv" (user + login versions) of every session
      # issued before this migration stays valid.
      add :security_version, :integer, null: false, default: 0
      add :email_verified_at, :utc_datetime_usec
      add :last_used_user_id, :binary_id
      timestamps()
    end

    execute("CREATE UNIQUE INDEX logins_email_unique_index ON logins (lower(email))")

    alter table(:users) do
      add :login_id, references(:logins, type: :binary_id, on_delete: :restrict)
      add :search_text, :text
      add :handle_changed_at, :utc_datetime_usec
    end

    execute("""
    INSERT INTO logins (id, email, password_hash, security_version, last_used_user_id, inserted_at, updated_at)
    SELECT gen_random_uuid(), u.email, u.password_hash, 0, u.id, u.inserted_at, now()
    FROM users u
    """)

    execute("""
    UPDATE users SET login_id = l.id
    FROM logins l
    WHERE l.last_used_user_id = users.id
    """)

    execute("""
    ALTER TABLE logins
    ADD CONSTRAINT logins_last_used_user_id_fkey
    FOREIGN KEY (last_used_user_id) REFERENCES users(id) ON DELETE SET NULL
    """)

    execute(
      "UPDATE users SET display_nickname = COALESCE(NULLIF(display_nickname, ''), nickname)"
    )

    execute("UPDATE users SET search_text = lower(display_nickname) || ' ' || nickname")

    alter table(:users) do
      modify :login_id, :binary_id, null: false
      modify :display_nickname, :string, null: false
      modify :search_text, :text, null: false, default: ""
    end

    create index(:users, [:login_id])

    execute("""
    CREATE INDEX users_search_text_trgm_index ON users USING gin (search_text gin_trgm_ops)
    """)

    execute("""
    CREATE INDEX users_handle_trgm_index ON users USING gin (nickname gin_trgm_ops)
    """)

    execute("DROP INDEX IF EXISTS users_email_unique_index")

    alter table(:users) do
      remove :email
      remove :password_hash
    end

    create table(:handle_reservations, primary_key: false) do
      add :handle, :string, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :reserved_until, :utc_datetime_usec, null: false
      timestamps(updated_at: false)
    end

    create index(:handle_reservations, [:user_id])

    execute("""
    CREATE OR REPLACE FUNCTION users_profile_cap() RETURNS trigger AS $$
    DECLARE
      profile_count integer;
    BEGIN
      IF TG_OP = 'UPDATE' AND NEW.login_id IS NOT DISTINCT FROM OLD.login_id THEN
        RETURN NEW;
      END IF;

      PERFORM 1 FROM logins WHERE id = NEW.login_id FOR UPDATE;
      SELECT count(*) INTO profile_count FROM users WHERE login_id = NEW.login_id;

      IF profile_count >= 3 THEN
        RAISE EXCEPTION 'a login holds at most 3 profiles'
          USING ERRCODE = 'check_violation', CONSTRAINT = 'users_profile_cap';
      END IF;

      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql
    """)

    execute("""
    CREATE TRIGGER users_profile_cap
    BEFORE INSERT OR UPDATE OF login_id ON users
    FOR EACH ROW EXECUTE FUNCTION users_profile_cap()
    """)
  end

  def down do
    execute("DROP TRIGGER IF EXISTS users_profile_cap ON users")
    execute("DROP FUNCTION IF EXISTS users_profile_cap()")
    drop table(:handle_reservations)

    alter table(:users) do
      add :email, :string
      add :password_hash, :string
    end

    execute("""
    UPDATE users SET email = l.email, password_hash = l.password_hash
    FROM logins l WHERE l.id = users.login_id
    """)

    # Several profiles shared one email; only the oldest keeps it.
    execute("""
    UPDATE users SET email = lower(nickname) || '+' || replace(id::text, '-', '') || '@placeholder.invalid'
    WHERE id IN (
      SELECT id FROM (
        SELECT id, row_number() OVER (PARTITION BY login_id ORDER BY inserted_at, id) AS position
        FROM users
      ) ranked WHERE position > 1
    )
    """)

    alter table(:users) do
      modify :email, :string, null: false
      modify :password_hash, :string, null: false
    end

    execute("""
    CREATE UNIQUE INDEX users_email_unique_index ON users (lower(email)) WHERE email IS NOT NULL
    """)

    execute("DROP INDEX IF EXISTS users_handle_trgm_index")
    execute("DROP INDEX IF EXISTS users_search_text_trgm_index")
    drop index(:users, [:login_id])

    alter table(:users) do
      modify :display_nickname, :string, null: true
      remove :login_id
      remove :search_text
      remove :handle_changed_at
    end

    drop table(:logins)
  end
end
