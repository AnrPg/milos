defmodule Palee.Repo.Migrations.ReleasedEmailReservations do
  @moduledoc """
  ADR-211: an address a login moved away from (ADR-207 email change) stays
  reserved for that login while its 7-day "this wasn't me" link works, so
  nobody else can sign up with it, or change to it, before the owner can
  take it back. Only the SHA-256 of the normalised address is stored
  (`InvitationEmail.digest/1`). A platform table like `logins`: no
  `organization_id`, never read by a tenant session, so no RLS.
  """
  use Ecto.Migration

  def change do
    create table(:released_email_reservations, primary_key: false) do
      add :address_digest, :binary, primary_key: true
      add :login_id, references(:logins, type: :binary_id, on_delete: :delete_all), null: false
      add :reserved_until, :utc_datetime_usec, null: false
      timestamps(type: :utc_datetime_usec)
    end

    create index(:released_email_reservations, [:login_id])
    create index(:released_email_reservations, [:reserved_until])
  end
end
