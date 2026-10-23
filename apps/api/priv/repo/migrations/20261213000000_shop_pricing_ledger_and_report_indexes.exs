defmodule Palee.Repo.Migrations.ShopPricingLedgerAndReportIndexes do
  @moduledoc """
  ADR-192: what the shop reports and pricing indicators need on top of
  ADR-190's schema.

  - `shop_variant_price_changes`: an append-only price-history ledger per
    variant. The database writes it (trigger on `shop_variants`), so every
    writer of a price - the catalog API, an import, a fix in psql - leaves a
    row, and no application path can forget to. Existing variants get their
    current price as an opening row at their creation time.
  - `shop_pricing_targets`: the target margin per product category (and one
    box-wide default, `category IS NULL`) in integer basis points, the input
    of the advisory cost-plus price range.
  - Report indexes: paid shop orders by paid time, paid finance payments by
    stream and business date, and the price ledger by variant and time.

  Both tables are tenant scoped (forced RLS, `palee_apply_tenant_context`)
  with composite foreign keys, like ADR-190.
  """

  use Ecto.Migration

  def up do
    create table(:shop_variant_price_changes, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :variant_id, :binary_id, null: false
      add :price_cents, :integer, null: false
      add :previous_price_cents, :integer
      add :cost_price_cents, :integer
      add :previous_cost_price_cents, :integer
      add :compare_at_price_cents, :integer
      add :currency, :string, null: false, default: "EUR"
      add :source, :string, null: false, default: "catalog"
      add :changed_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :changed_at, :utc_datetime_usec, null: false
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    execute("""
    ALTER TABLE shop_variant_price_changes
    ADD CONSTRAINT shop_variant_price_changes_variant_fkey
    FOREIGN KEY (variant_id, organization_id)
    REFERENCES shop_variants (id, organization_id) ON DELETE CASCADE
    """)

    create constraint(:shop_variant_price_changes, :shop_variant_price_changes_amounts_check,
             check:
               "price_cents >= 0 AND (previous_price_cents IS NULL OR previous_price_cents >= 0) AND (cost_price_cents IS NULL OR cost_price_cents >= 0) AND (compare_at_price_cents IS NULL OR compare_at_price_cents >= 0)"
           )

    create constraint(:shop_variant_price_changes, :shop_variant_price_changes_source_check,
             check: "source IN ('catalog', 'opening')"
           )

    create index(:shop_variant_price_changes, [:variant_id, :changed_at])
    create index(:shop_variant_price_changes, [:organization_id, :changed_at])

    execute("""
    CREATE OR REPLACE FUNCTION palee_shop_variant_price_changes_append_only() RETURNS trigger AS $$
    BEGIN
      RAISE EXCEPTION 'shop_variant_price_changes is append-only';
    END;
    $$ LANGUAGE plpgsql
    """)

    # Cascades from a deleted variant or business still remove the rows
    # (pg_trigger_depth() > 0 inside a cascade).
    execute("""
    CREATE TRIGGER shop_variant_price_changes_append_only
    BEFORE UPDATE OR DELETE ON shop_variant_price_changes
    FOR EACH ROW WHEN (pg_trigger_depth() = 0)
    EXECUTE FUNCTION palee_shop_variant_price_changes_append_only()
    """)

    execute("""
    CREATE OR REPLACE FUNCTION palee_shop_variant_price_history() RETURNS trigger AS $$
    BEGIN
      IF TG_OP = 'INSERT'
         OR NEW.price_cents IS DISTINCT FROM OLD.price_cents
         OR NEW.cost_price_cents IS DISTINCT FROM OLD.cost_price_cents THEN
        INSERT INTO shop_variant_price_changes (
          id, organization_id, variant_id, price_cents, previous_price_cents,
          cost_price_cents, previous_cost_price_cents, compare_at_price_cents,
          currency, source, changed_by_id, changed_at, inserted_at
        ) VALUES (
          gen_random_uuid(), NEW.organization_id, NEW.id, NEW.price_cents,
          CASE WHEN TG_OP = 'UPDATE' THEN OLD.price_cents END,
          NEW.cost_price_cents,
          CASE WHEN TG_OP = 'UPDATE' THEN OLD.cost_price_cents END,
          NEW.compare_at_price_cents, NEW.currency, 'catalog',
          (SELECT id FROM users
            WHERE id = NULLIF(current_setting('app.user_id', true), '')::uuid),
          clock_timestamp(), clock_timestamp()
        );
      END IF;

      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql
    """)

    execute("""
    CREATE TRIGGER shop_variants_price_history
    AFTER INSERT OR UPDATE OF price_cents, cost_price_cents ON shop_variants
    FOR EACH ROW EXECUTE FUNCTION palee_shop_variant_price_history()
    """)

    # Opening rows for variants that existed before the ledger, written
    # before RLS is enabled on the new table (no tenant scope here).
    execute("""
    INSERT INTO shop_variant_price_changes (
      id, organization_id, variant_id, price_cents, cost_price_cents,
      compare_at_price_cents, currency, source, changed_at, inserted_at
    )
    SELECT gen_random_uuid(), organization_id, id, price_cents, cost_price_cents,
           compare_at_price_cents, currency, 'opening', inserted_at, now()
    FROM shop_variants
    """)

    create table(:shop_pricing_targets, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      # NULL = the box-wide default.
      add :category, :string
      add :target_margin_bp, :integer, null: false
      add :updated_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      timestamps(type: :utc_datetime_usec)
    end

    create constraint(:shop_pricing_targets, :shop_pricing_targets_margin_check,
             check: "target_margin_bp BETWEEN 0 AND 9500"
           )

    execute("""
    CREATE UNIQUE INDEX shop_pricing_targets_category_index
    ON shop_pricing_targets (organization_id, category) NULLS NOT DISTINCT
    """)

    for table <- ~w(shop_variant_price_changes shop_pricing_targets) do
      execute("""
      CREATE TRIGGER #{table}_apply_tenant_context
      BEFORE INSERT OR UPDATE ON #{table}
      FOR EACH ROW EXECUTE FUNCTION palee_apply_tenant_context()
      """)

      execute("""
      CREATE POLICY #{table}_tenant_policy ON #{table}
      USING (organization_id = NULLIF(current_setting('app.organization_id', true), '')::uuid)
      WITH CHECK (organization_id = NULLIF(current_setting('app.organization_id', true), '')::uuid)
      """)

      execute("ALTER TABLE #{table} ENABLE ROW LEVEL SECURITY")
      execute("ALTER TABLE #{table} FORCE ROW LEVEL SECURITY")
    end

    # Report reads (ADR-192 §4): paid orders by paid time per business.
    create index(:shop_orders, [:organization_id, :paid_at],
             where: "paid_at IS NOT NULL",
             name: :shop_orders_paid_at_index
           )

    # Finance revenue by stream (ADR-192 §2) and the reconciliation: paid,
    # live payments per business, stream and business date.
    create index(:membership_payments, [:organization_id, :revenue_stream, :paid_on],
             where: "deleted_at IS NULL AND payment_status = 'paid'",
             name: :membership_payments_paid_stream_index
           )
  end

  def down do
    drop index(:membership_payments, [:organization_id, :revenue_stream, :paid_on],
           name: :membership_payments_paid_stream_index
         )

    drop index(:shop_orders, [:organization_id, :paid_at], name: :shop_orders_paid_at_index)

    execute("DROP TRIGGER IF EXISTS shop_variants_price_history ON shop_variants")
    execute("DROP FUNCTION IF EXISTS palee_shop_variant_price_history()")
    drop table(:shop_pricing_targets)
    drop table(:shop_variant_price_changes)
    execute("DROP FUNCTION IF EXISTS palee_shop_variant_price_changes_append_only()")
  end
end
