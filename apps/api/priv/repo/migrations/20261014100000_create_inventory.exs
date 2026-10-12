defmodule MilosTraining.Repo.Migrations.CreateInventory do
  use Ecto.Migration

  # ADR-104: the gym's inventory. Machines (training machines and appliances)
  # with their state and maintenance log; consumables with stock, where to buy
  # them, and every restock and use.
  @tables ~w(inventory_machines inventory_machine_events inventory_supplies inventory_supply_movements inventory_supply_reports)

  def change do
    create table(:inventory_machines, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :name, :string, null: false
      add :category, :string, null: false, default: "training"
      add :brand, :string
      add :model, :string
      add :serial_number, :string
      add :location_id, :binary_id
      add :quantity, :integer, null: false, default: 1
      add :purchased_on, :date
      add :purchase_price_cents, :integer
      add :warranty_until, :date
      add :service_contact, :text
      add :service_interval_days, :integer
      add :last_serviced_on, :date
      add :status, :string, null: false, default: "working"
      add :notes, :text
      add :archived_at, :utc_datetime_usec
      timestamps(type: :utc_datetime_usec)
    end

    create constraint(:inventory_machines, :inventory_machines_category_check,
             check: "category IN ('training', 'appliance')"
           )

    create constraint(:inventory_machines, :inventory_machines_status_check,
             check: "status IN ('working', 'needs_attention', 'out_of_order', 'retired')"
           )

    create unique_index(:inventory_machines, [:id, :organization_id],
             name: :inventory_machines_id_organization_index
           )

    create index(:inventory_machines, [:organization_id, :status])

    create table(:inventory_machine_events, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :machine_id, :binary_id, null: false
      add :user_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :kind, :string, null: false
      # Canonical fields of a note (ADR-104), next to the free text in `body`.
      add :severity, :string
      add :symptom, :string
      add :usable, :boolean
      add :body, :text
      add :cost_cents, :integer
      add :occurred_at, :utc_datetime_usec, null: false
      timestamps(type: :utc_datetime_usec)
    end

    create constraint(:inventory_machine_events, :inventory_machine_events_kind_check,
             check:
               "kind IN ('note', 'issue', 'out_of_order', 'repair_requested', 'maintenance', 'repaired', 'retired')"
           )

    create constraint(:inventory_machine_events, :inventory_machine_events_severity_check,
             check: "severity IS NULL OR severity IN ('low', 'medium', 'high', 'safety')"
           )

    create constraint(:inventory_machine_events, :inventory_machine_events_symptom_check,
             check:
               "symptom IS NULL OR symptom IN ('noise', 'not_starting', 'broken_part', 'leak', 'electrical', 'display', 'cleanliness', 'other')"
           )

    execute(
      """
      ALTER TABLE inventory_machine_events
      ADD CONSTRAINT inventory_machine_events_machine_fkey
      FOREIGN KEY (machine_id, organization_id)
      REFERENCES inventory_machines (id, organization_id) ON DELETE CASCADE
      """,
      "ALTER TABLE inventory_machine_events DROP CONSTRAINT inventory_machine_events_machine_fkey"
    )

    create index(:inventory_machine_events, [:machine_id, :occurred_at])
    create index(:inventory_machine_events, [:organization_id, :occurred_at])

    create table(:inventory_supplies, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :name, :string, null: false
      add :description, :text
      add :brand, :string
      add :shop, :string
      add :url, :string, size: 2048
      add :unit, :string
      add :unit_price_cents, :integer
      add :quantity, :integer, null: false, default: 0
      add :consumption_speed, :string, null: false, default: "regular"
      add :reorder_level, :integer
      add :stock_status, :string, null: false, default: "ok"
      add :archived_at, :utc_datetime_usec
      timestamps(type: :utc_datetime_usec)
    end

    create constraint(:inventory_supplies, :inventory_supplies_speed_check,
             check: "consumption_speed IN ('fast', 'regular', 'slow')"
           )

    create constraint(:inventory_supplies, :inventory_supplies_quantity_check,
             check: "quantity >= 0"
           )

    create unique_index(:inventory_supplies, [:id, :organization_id],
             name: :inventory_supplies_id_organization_index
           )

    create index(:inventory_supplies, [:organization_id])

    create table(:inventory_supply_movements, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :supply_id, :binary_id, null: false
      add :user_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :kind, :string, null: false
      add :quantity, :integer, null: false
      add :unit_price_cents, :integer
      add :total_cents, :integer
      add :note, :text
      add :occurred_at, :utc_datetime_usec, null: false
      timestamps(type: :utc_datetime_usec)
    end

    create constraint(:inventory_supply_movements, :inventory_supply_movements_kind_check,
             check: "kind IN ('restock', 'consume', 'adjust')"
           )

    execute(
      """
      ALTER TABLE inventory_supply_movements
      ADD CONSTRAINT inventory_supply_movements_supply_fkey
      FOREIGN KEY (supply_id, organization_id)
      REFERENCES inventory_supplies (id, organization_id) ON DELETE CASCADE
      """,
      "ALTER TABLE inventory_supply_movements DROP CONSTRAINT inventory_supply_movements_supply_fkey"
    )

    create index(:inventory_supply_movements, [:supply_id, :occurred_at])
    create index(:inventory_supply_movements, [:organization_id, :occurred_at])

    # "Running low" reports: who flagged it, when, with what note; a restock
    # resolves the open ones (and records who restocked).
    create table(:inventory_supply_reports, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :supply_id, :binary_id, null: false
      add :user_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      # Canonical fields (ADR-104), next to the free-text `note`.
      add :level, :string, null: false, default: "running_low"
      add :seen_quantity, :integer
      add :place, :string
      add :note, :text
      add :reported_at, :utc_datetime_usec, null: false
      add :resolved_at, :utc_datetime_usec
      add :resolved_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      timestamps(type: :utc_datetime_usec)
    end

    execute(
      """
      ALTER TABLE inventory_supply_reports
      ADD CONSTRAINT inventory_supply_reports_supply_fkey
      FOREIGN KEY (supply_id, organization_id)
      REFERENCES inventory_supplies (id, organization_id) ON DELETE CASCADE
      """,
      "ALTER TABLE inventory_supply_reports DROP CONSTRAINT inventory_supply_reports_supply_fkey"
    )

    create constraint(:inventory_supply_reports, :inventory_supply_reports_level_check,
             check: "level IN ('running_low', 'empty')"
           )

    create index(:inventory_supply_reports, [:supply_id, :reported_at])

    create index(:inventory_supply_reports, [:organization_id],
             where: "resolved_at IS NULL",
             name: :inventory_supply_reports_open_index
           )

    for table <- @tables do
      execute(
        """
        CREATE TRIGGER #{table}_apply_tenant_context
        BEFORE INSERT OR UPDATE ON #{table}
        FOR EACH ROW EXECUTE FUNCTION milos_apply_tenant_context()
        """,
        "DROP TRIGGER IF EXISTS #{table}_apply_tenant_context ON #{table}"
      )

      execute(
        """
        CREATE POLICY #{table}_tenant_policy ON #{table}
        USING (organization_id = NULLIF(current_setting('app.organization_id', true), '')::uuid)
        WITH CHECK (organization_id = NULLIF(current_setting('app.organization_id', true), '')::uuid)
        """,
        "DROP POLICY IF EXISTS #{table}_tenant_policy ON #{table}"
      )

      execute(
        "ALTER TABLE #{table} ENABLE ROW LEVEL SECURITY",
        "ALTER TABLE #{table} DISABLE ROW LEVEL SECURITY"
      )

      execute(
        "ALTER TABLE #{table} FORCE ROW LEVEL SECURITY",
        "ALTER TABLE #{table} NO FORCE ROW LEVEL SECURITY"
      )
    end
  end
end
