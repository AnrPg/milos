defmodule Palee.Repo.Migrations.CreateShop do
  @moduledoc """
  ADR-190: the e-shop. Products and their variants, an append-only stock
  ledger per variant and branch with its cached projection, and orders with
  their lines. Money stays in Finance: an order's invoice, payments and
  refunds are Finance rows tagged `revenue_stream = 'shop'` and pointing back
  here (`source_type` / `source_id`).

  Every table is tenant scoped (forced RLS, `palee_apply_tenant_context`) with
  composite `(id, organization_id)` foreign keys, like ADR-104.
  """

  use Ecto.Migration

  @tables ~w(shop_products shop_variants shop_stock_movements shop_stock_levels shop_orders shop_order_lines)

  def up do
    create table(:shop_products, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :title, :string, null: false
      add :description, :text
      add :category, :string
      add :media_ids, {:array, :uuid}, null: false, default: []
      # `[{name, values}]`, at most two (size × colour).
      add :options, :map, null: false, default: %{}
      add :status, :string, null: false, default: "draft"
      add :visibility, :string, null: false, default: "members_only"
      add :sell_in_app, :boolean, null: false, default: true
      add :sell_at_desk, :boolean, null: false, default: true
      add :member_discount_applies, :boolean, null: false, default: false
      add :per_person_limit, :integer
      # ADR-186 §8 covering item: valid at every branch or the listed ones.
      add :all_locations, :boolean, null: false, default: true
      add :location_ids, {:array, :uuid}, null: false, default: []
      add :position, :integer, null: false, default: 0
      add :published_at, :utc_datetime_usec
      add :archived_at, :utc_datetime_usec
      add :created_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      timestamps(type: :utc_datetime_usec)
    end

    create constraint(:shop_products, :shop_products_status_check,
             check: "status IN ('draft', 'published', 'archived')"
           )

    create constraint(:shop_products, :shop_products_visibility_check,
             check: "visibility IN ('members_only', 'anyone')"
           )

    create constraint(:shop_products, :shop_products_location_scope_check,
             check: "all_locations OR cardinality(location_ids) BETWEEN 1 AND 200"
           )

    create constraint(:shop_products, :shop_products_limit_check,
             check: "per_person_limit IS NULL OR per_person_limit > 0"
           )

    create unique_index(:shop_products, [:id, :organization_id],
             name: :shop_products_id_organization_index
           )

    create index(:shop_products, [:organization_id, :status])

    create table(:shop_variants, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :product_id, :binary_id, null: false
      add :title, :string
      add :option_values, :map, null: false, default: %{}
      add :sku, :string
      add :barcode, :string
      add :price_cents, :integer, null: false
      add :currency, :string, null: false, default: "EUR"
      add :compare_at_price_cents, :integer
      add :cost_price_cents, :integer
      # Finance has no tax model yet: a label only (TD-190).
      add :tax_class, :string
      add :low_stock_threshold, :integer
      add :track_inventory, :boolean, null: false, default: true
      add :stock_status, :string, null: false, default: "out"
      add :position, :integer, null: false, default: 0
      add :archived_at, :utc_datetime_usec
      timestamps(type: :utc_datetime_usec)
    end

    execute("""
    ALTER TABLE shop_variants
    ADD CONSTRAINT shop_variants_product_fkey
    FOREIGN KEY (product_id, organization_id)
    REFERENCES shop_products (id, organization_id) ON DELETE CASCADE
    """)

    create constraint(:shop_variants, :shop_variants_amounts_check,
             check:
               "price_cents >= 0 AND (compare_at_price_cents IS NULL OR compare_at_price_cents >= 0) AND (cost_price_cents IS NULL OR cost_price_cents >= 0)"
           )

    create constraint(:shop_variants, :shop_variants_threshold_check,
             check: "low_stock_threshold IS NULL OR low_stock_threshold >= 0"
           )

    create constraint(:shop_variants, :shop_variants_stock_status_check,
             check: "stock_status IN ('ok', 'low', 'critical', 'out')"
           )

    create constraint(:shop_variants, :shop_variants_tax_class_check,
             check:
               "tax_class IS NULL OR tax_class IN ('standard', 'reduced', 'super_reduced', 'zero', 'exempt')"
           )

    create unique_index(:shop_variants, [:id, :organization_id],
             name: :shop_variants_id_organization_index
           )

    create unique_index(:shop_variants, [:organization_id, :sku],
             where: "sku IS NOT NULL AND archived_at IS NULL",
             name: :shop_variants_organization_sku_index
           )

    create index(:shop_variants, [:product_id])

    # The ledger. Append-only: rows are never updated or deleted (trigger).
    # `quantity` is the signed change of on-hand stock; `reserve` / `release`
    # move the reserved count instead.
    create table(:shop_stock_movements, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :variant_id, :binary_id, null: false
      add :location_id, :binary_id
      add :kind, :string, null: false
      add :quantity, :integer, null: false
      add :reason, :string
      add :note, :text
      add :unit_cost_cents, :integer
      add :order_id, :binary_id
      add :order_line_id, :binary_id
      # A transfer is two rows (out and in) sharing `transfer_id`.
      add :transfer_id, :binary_id
      add :user_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :occurred_at, :utc_datetime_usec, null: false
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    execute("""
    ALTER TABLE shop_stock_movements
    ADD CONSTRAINT shop_stock_movements_variant_fkey
    FOREIGN KEY (variant_id, organization_id)
    REFERENCES shop_variants (id, organization_id) ON DELETE CASCADE
    """)

    create constraint(:shop_stock_movements, :shop_stock_movements_kind_check,
             check:
               "kind IN ('receive', 'sale', 'refund_restock', 'adjustment', 'transfer', 'reserve', 'release')"
           )

    create constraint(:shop_stock_movements, :shop_stock_movements_sign_check,
             check: """
             (kind IN ('receive', 'refund_restock') AND quantity > 0)
             OR (kind = 'sale' AND quantity < 0)
             OR (kind IN ('reserve', 'release') AND quantity > 0)
             OR (kind IN ('adjustment', 'transfer') AND quantity <> 0)
             """
           )

    create constraint(:shop_stock_movements, :shop_stock_movements_reason_check,
             check:
               "kind <> 'adjustment' OR reason IN ('recount', 'damage', 'loss', 'return', 'other')"
           )

    create index(:shop_stock_movements, [:variant_id, :occurred_at])
    create index(:shop_stock_movements, [:organization_id, :occurred_at])
    create index(:shop_stock_movements, [:order_line_id], where: "order_line_id IS NOT NULL")

    execute("""
    CREATE OR REPLACE FUNCTION palee_shop_stock_movements_append_only() RETURNS trigger AS $$
    BEGIN
      RAISE EXCEPTION 'shop_stock_movements is append-only';
    END;
    $$ LANGUAGE plpgsql
    """)

    execute("""
    CREATE TRIGGER shop_stock_movements_append_only
    BEFORE UPDATE OR DELETE ON shop_stock_movements
    FOR EACH ROW WHEN (pg_trigger_depth() = 0)
    EXECUTE FUNCTION palee_shop_stock_movements_append_only()
    """)

    # The projection of the ledger: what is on the shelf and what open orders
    # hold, per variant and branch (no branch = the business's one stock).
    # The checks are the never-oversell guard: a sale or reservation that
    # would take more than is available fails in the same statement.
    create table(:shop_stock_levels, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :variant_id, :binary_id, null: false
      add :location_id, :binary_id
      add :on_hand, :integer, null: false, default: 0
      add :reserved, :integer, null: false, default: 0
      timestamps(type: :utc_datetime_usec)
    end

    execute("""
    ALTER TABLE shop_stock_levels
    ADD CONSTRAINT shop_stock_levels_variant_fkey
    FOREIGN KEY (variant_id, organization_id)
    REFERENCES shop_variants (id, organization_id) ON DELETE CASCADE
    """)

    create constraint(:shop_stock_levels, :shop_stock_levels_available_check,
             check: "on_hand >= 0 AND reserved >= 0 AND reserved <= on_hand"
           )

    execute("""
    CREATE UNIQUE INDEX shop_stock_levels_variant_location_index
    ON shop_stock_levels (variant_id, location_id) NULLS NOT DISTINCT
    """)

    create index(:shop_stock_levels, [:organization_id])

    create table(:shop_orders, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :number, :integer, null: false
      add :channel, :string, null: false
      add :status, :string, null: false, default: "placed"
      add :payment_status, :string, null: false, default: "pending_payment"
      add :payment_mode, :string, null: false
      # null = walk-in at the desk.
      add :user_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :membership_id, :binary_id
      add :customer_name, :string
      add :pickup_location_id, :binary_id
      add :currency, :string, null: false, default: "EUR"
      add :subtotal_cents, :integer, null: false, default: 0
      add :discount_cents, :integer, null: false, default: 0
      add :total_cents, :integer, null: false, default: 0
      add :paid_cents, :integer, null: false, default: 0
      add :refunded_cents, :integer, null: false, default: 0
      # Attribution (ADR-190): where the order came from.
      add :source, :string, null: false, default: "direct"
      add :source_ref_id, :binary_id
      add :promotion_code, :string
      add :finance_invoice_id, :binary_id
      add :fiscal_receipt_ref, :string
      add :payment_provider, :string
      add :payment_reference, :string
      add :note, :text
      # Idempotency (ADR-190): a retried placement or capture returns the
      # first result instead of a second order or payment.
      add :idempotency_key, :string, null: false
      add :payment_idempotency_key, :string
      add :placed_at, :utc_datetime_usec, null: false
      add :expires_at, :utc_datetime_usec
      add :paid_at, :utc_datetime_usec
      add :ready_at, :utc_datetime_usec
      add :picked_up_at, :utc_datetime_usec
      add :cancelled_at, :utc_datetime_usec
      add :cancel_reason, :string
      add :created_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :handled_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      timestamps(type: :utc_datetime_usec)
    end

    create constraint(:shop_orders, :shop_orders_channel_check,
             check: "channel IN ('online', 'pos')"
           )

    create constraint(:shop_orders, :shop_orders_status_check,
             check: "status IN ('placed', 'ready_for_pickup', 'picked_up', 'cancelled')"
           )

    create constraint(:shop_orders, :shop_orders_payment_status_check,
             check:
               "payment_status IN ('pending_payment', 'paid', 'partially_refunded', 'refunded', 'void')"
           )

    create constraint(:shop_orders, :shop_orders_payment_mode_check,
             check:
               "payment_mode IN ('at_pickup', 'on_account', 'online', 'cash', 'card_manual', 'bank_transfer', 'other')"
           )

    create constraint(:shop_orders, :shop_orders_source_check,
             check:
               "source IN ('direct', 'club_post', 'promotion_code', 'desk', 'public_page', 'other')"
           )

    create constraint(:shop_orders, :shop_orders_amounts_check,
             check:
               "subtotal_cents >= 0 AND discount_cents >= 0 AND total_cents >= 0 AND paid_cents >= 0 AND refunded_cents >= 0 AND refunded_cents <= paid_cents"
           )

    create constraint(:shop_orders, :shop_orders_online_buyer_check,
             check: "channel = 'pos' OR user_id IS NOT NULL"
           )

    create unique_index(:shop_orders, [:id, :organization_id],
             name: :shop_orders_id_organization_index
           )

    create unique_index(:shop_orders, [:organization_id, :number],
             name: :shop_orders_organization_number_index
           )

    create unique_index(:shop_orders, [:organization_id, :idempotency_key],
             name: :shop_orders_idempotency_index
           )

    create index(:shop_orders, [:organization_id, :status, :placed_at])
    create index(:shop_orders, [:user_id, :placed_at])
    create index(:shop_orders, [:finance_invoice_id], where: "finance_invoice_id IS NOT NULL")

    create table(:shop_order_lines, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :order_id, :binary_id, null: false
      add :product_id, :binary_id, null: false
      add :variant_id, :binary_id, null: false
      add :product_title, :string, null: false
      add :variant_title, :string
      add :sku, :string
      add :quantity, :integer, null: false
      add :unit_price_cents, :integer, null: false
      add :cost_price_cents, :integer
      add :tax_class, :string
      add :discount_cents, :integer, null: false, default: 0
      add :total_cents, :integer, null: false
      add :refunded_quantity, :integer, null: false, default: 0
      add :refunded_cents, :integer, null: false, default: 0
      add :location_id, :binary_id
      add :finance_invoice_line_id, :binary_id
      timestamps(type: :utc_datetime_usec)
    end

    execute("""
    ALTER TABLE shop_order_lines
    ADD CONSTRAINT shop_order_lines_order_fkey
    FOREIGN KEY (order_id, organization_id)
    REFERENCES shop_orders (id, organization_id) ON DELETE CASCADE
    """)

    execute("""
    ALTER TABLE shop_order_lines
    ADD CONSTRAINT shop_order_lines_variant_fkey
    FOREIGN KEY (variant_id, organization_id)
    REFERENCES shop_variants (id, organization_id)
    """)

    execute("""
    ALTER TABLE shop_order_lines
    ADD CONSTRAINT shop_order_lines_product_fkey
    FOREIGN KEY (product_id, organization_id)
    REFERENCES shop_products (id, organization_id)
    """)

    create constraint(:shop_order_lines, :shop_order_lines_amounts_check,
             check:
               "quantity > 0 AND unit_price_cents >= 0 AND discount_cents >= 0 AND total_cents >= 0 AND refunded_quantity BETWEEN 0 AND quantity AND refunded_cents BETWEEN 0 AND total_cents"
           )

    create index(:shop_order_lines, [:order_id])
    create index(:shop_order_lines, [:variant_id])
    create index(:shop_order_lines, [:organization_id, :product_id])

    for table <- @tables do
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

    add_notification_types(~w(shop_stock_low shop_order_placed shop_order_ready))
  end

  def down do
    execute(
      "DELETE FROM notifications WHERE type IN ('shop_stock_low', 'shop_order_placed', 'shop_order_ready')"
    )

    rewrite_notification_types(&(&1 -- ~w(shop_stock_low shop_order_placed shop_order_ready)))

    for table <- Enum.reverse(@tables), do: drop(table(String.to_atom(table)))
    execute("DROP FUNCTION IF EXISTS palee_shop_stock_movements_append_only()")
  end

  defp add_notification_types(types), do: rewrite_notification_types(&Enum.uniq(&1 ++ types))

  defp rewrite_notification_types(change) do
    flush()

    %{rows: [[definition]]} =
      repo().query!("""
      SELECT pg_get_constraintdef(oid) FROM pg_constraint
      WHERE conname = 'notifications_type_check' AND conrelid = 'notifications'::regclass
      """)

    current = Regex.scan(~r/'([a-z0-9_]+)'/, definition) |> Enum.map(&List.last/1)

    execute("ALTER TABLE notifications DROP CONSTRAINT notifications_type_check")

    execute(
      "ALTER TABLE notifications ADD CONSTRAINT notifications_type_check CHECK (type IN (#{Enum.map_join(change.(current), ", ", &"'#{&1}'")}))"
    )
  end
end
