defmodule MilosTraining.Repo.Migrations.BackfillAndRequireUserEmail do
  use Ecto.Migration

  # F-10 follow-up: email is now mandatory. Existing accounts predate the
  # column, so they are backfilled before the NOT NULL constraint goes on.
  #
  # Placeholders use the RFC 2606 reserved `.invalid` TLD, which is guaranteed
  # never to resolve — a fabricated address must never be able to receive mail,
  # and must be obviously fake to anyone reading the table later. They are
  # derived from the (unique) nickname so they satisfy the unique index.

  @vendor_email "stergios.gr95@gmail.com"

  def up do
    # The real address can only belong to one account — it is a unique index.
    # Awarding it to the earliest vendor keeps this deterministic and rerunnable
    # rather than depending on row order.
    execute("""
    UPDATE users SET email = '#{@vendor_email}'
    WHERE id = (
      SELECT u.id
      FROM users u
      JOIN vendors v ON v.user_id = u.id
      WHERE v.status = 'active' AND u.email IS NULL
      ORDER BY u.inserted_at ASC, u.id ASC
      LIMIT 1
    )
    """)

    # Everyone else, including any additional vendors.
    execute("""
    UPDATE users
    SET email = lower(nickname) || '@placeholder.invalid'
    WHERE email IS NULL
    """)

    # Guard against a nickname that somehow collided after lowercasing, so the
    # NOT NULL below cannot fail on a half-filled table.
    execute("""
    UPDATE users
    SET email = lower(nickname) || '+' || replace(id::text, '-', '') || '@placeholder.invalid'
    WHERE email IS NULL
    """)

    alter table(:users) do
      modify(:email, :string, null: false)
    end
  end

  def down do
    alter table(:users) do
      modify(:email, :string, null: true)
    end

    execute("UPDATE users SET email = NULL WHERE email LIKE '%@placeholder.invalid'")
    execute("UPDATE users SET email = NULL WHERE email = '#{@vendor_email}'")
  end
end
