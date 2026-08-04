defmodule MilosTraining.Repo.Migrations.CreateOrganizationPrimitives do
  use Ecto.Migration

  def change do
    create table(:organizations, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :slug, :string, null: false
      add :name, :string, null: false
      add :status, :string, null: false, default: "active"

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:organizations, [:slug])
    create index(:organizations, [:status])

    create constraint(:organizations, :organizations_status_check,
             check: "status IN ('active', 'suspended', 'archived')"
           )

    create table(:organization_memberships, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id,
          references(:organizations, type: :binary_id, on_delete: :delete_all),
          null: false

      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :role, :string, null: false
      add :status, :string, null: false, default: "active"
      add :joined_at, :utc_datetime_usec
      add :invited_by_user_id, references(:users, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:organization_memberships, [:organization_id, :user_id])
    create index(:organization_memberships, [:user_id])
    create index(:organization_memberships, [:organization_id, :role])
    create index(:organization_memberships, [:organization_id, :status])

    create constraint(:organization_memberships, :organization_memberships_role_check,
             check: "role IN ('owner', 'admin', 'coach', 'member', 'athlete')"
           )

    create constraint(:organization_memberships, :organization_memberships_status_check,
             check: "status IN ('invited', 'active', 'suspended', 'revoked')"
           )

    create table(:registration_invitations, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id,
          references(:organizations, type: :binary_id, on_delete: :delete_all),
          null: false

      add :token_digest, :binary, null: false
      add :role, :string, null: false
      add :expires_at, :utc_datetime_usec, null: false
      add :redeemed_at, :utc_datetime_usec
      add :revoked_at, :utc_datetime_usec
      add :issued_by_user_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :redeemed_by_user_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :intended_email_digest, :binary

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:registration_invitations, [:token_digest])
    create index(:registration_invitations, [:organization_id, :expires_at])
    create index(:registration_invitations, [:organization_id, :role])
    create index(:registration_invitations, [:issued_by_user_id])
    create index(:registration_invitations, [:redeemed_by_user_id])

    create constraint(:registration_invitations, :registration_invitations_role_check,
             check: "role IN ('owner', 'admin', 'coach', 'member', 'athlete')"
           )

    create constraint(
             :registration_invitations,
             :registration_invitations_terminal_state_check,
             check: "NOT (redeemed_at IS NOT NULL AND revoked_at IS NOT NULL)"
           )

    create table(:organization_domains, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id,
          references(:organizations, type: :binary_id, on_delete: :delete_all),
          null: false

      add :host, :string, null: false
      add :verified_at, :utc_datetime_usec
      add :primary, :boolean, null: false, default: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:organization_domains, [:host])
    create index(:organization_domains, [:organization_id])

    create unique_index(:organization_domains, [:organization_id],
             where: "\"primary\" = true",
             name: :organization_domains_one_primary_per_organization
           )

    create table(:organization_settings, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id,
          references(:organizations, type: :binary_id, on_delete: :delete_all),
          null: false

      add :timezone, :string, null: false, default: "UTC"
      add :default_locale, :string, null: false, default: "en"
      add :invitation_lifetime_seconds, :integer, null: false, default: 604_800
      add :settings, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:organization_settings, [:organization_id])

    create constraint(:organization_settings, :organization_settings_invitation_lifetime_check,
             check: "invitation_lifetime_seconds BETWEEN 300 AND 604800"
           )
  end
end
