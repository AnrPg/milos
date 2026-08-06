defmodule MilosTraining.Repo.Migrations.AddEmailToUsers do
  use Ecto.Migration

  # F-10: registration_invitations.intended_email_digest was computed at issue
  # time but could never be checked, because accounts carried no email at all -
  # it was the only email-related column in the schema. Adding it here so the
  # digest becomes enforceable at redemption.
  #
  # Deliberately nullable: every existing account predates this column and
  # there is no source to backfill from. Enforcement therefore keys off
  # "does this account have a matching email", not "does every account have
  # an email" - see RedeemInvitation.

  def up do
    alter table(:users) do
      add(:email, :string)
    end

    # Addresses are compared case-insensitively; the digest is computed over
    # the downcased, trimmed form, so uniqueness must agree with that.
    execute("""
    CREATE UNIQUE INDEX users_email_unique_index
    ON users (lower(email))
    WHERE email IS NOT NULL
    """)
  end

  def down do
    execute("DROP INDEX IF EXISTS users_email_unique_index")

    alter table(:users) do
      remove(:email)
    end
  end
end
