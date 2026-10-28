defmodule Palee.Repo.Migrations.LoginDevices do
  @moduledoc """
  ADR-208: the devices each login has signed in from, so a sign-in from a
  device never seen before can be told to the person by email.

  `device_hash` is the SHA-256 of the device's random id and its coarse
  client and platform (`Identity.Domain.SignInDevice`); the raw id is never
  stored. `sign_ins` counts password sign-ins (a refresh does not count);
  a device remembered at sign-up starts at 0, so the first sign-in after
  sign-up never alerts.

  A platform table keyed by the login, like ADR-187's `login_recovery_codes`:
  written by the unauthenticated sign-in request, never read by a tenant
  session, so it carries no RLS.
  """
  use Ecto.Migration

  def change do
    create table(:login_devices, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :login_id, references(:logins, type: :binary_id, on_delete: :delete_all), null: false
      add :device_hash, :binary, null: false
      add :client, :string
      add :platform, :string
      add :sign_ins, :integer, null: false, default: 0
      add :first_seen_at, :utc_datetime_usec, null: false
      add :last_seen_at, :utc_datetime_usec, null: false
    end

    create unique_index(:login_devices, [:login_id, :device_hash])
    create index(:login_devices, [:login_id, :last_seen_at])
  end
end
