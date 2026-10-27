defmodule Palee.Repo.Migrations.PendingEmailChanges do
  @moduledoc """
  ADR-207: a login's email changes only once the new address confirms it.

  - `login_email_changes`: the one pending change of a login (the new
    address, when it was asked for and when it lapses). The login keeps its
    current address for sign-in and resets until the link is opened.
  - `logins.email_change_locked_until`: set by "this wasn't me" on the old
    address; no new change can be asked for before then, unless a password
    reset lifts it.

  Platform tables like `logins` and ADR-203's link tokens: written by the
  system and the person's own requests, never read by a tenant session, and
  with no `organization_id`, so they carry no RLS.
  """
  use Ecto.Migration

  def change do
    create table(:login_email_changes, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :login_id, references(:logins, type: :binary_id, on_delete: :delete_all), null: false
      add :new_email, :string, null: false
      add :requested_at, :utc_datetime_usec, null: false
      add :expires_at, :utc_datetime_usec, null: false
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:login_email_changes, [:login_id])

    alter table(:logins) do
      add :email_change_locked_until, :utc_datetime_usec
    end
  end
end
