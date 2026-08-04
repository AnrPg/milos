defmodule MilosTraining.Repo.Migrations.AddPlatformProvisioning do
  use Ecto.Migration

  def change do
    create table(:platform_owners, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :status, :string, null: false, default: "active"
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:platform_owners, [:user_id])

    create constraint(:platform_owners, :platform_owners_status_check,
             check: "status IN ('active', 'revoked')"
           )

    create table(:organization_provisioning_events, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :restrict),
        null: false

      add :platform_owner_user_id, references(:users, type: :binary_id, on_delete: :restrict),
        null: false

      add :event, :string, null: false
      add :metadata, :map, null: false, default: %{}
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:organization_provisioning_events, [:organization_id, :inserted_at])

    alter table(:organization_settings) do
      add :brand_name, :string
      add :brand_logo_url, :string
      add :brand_primary_color, :string
    end
  end
end
