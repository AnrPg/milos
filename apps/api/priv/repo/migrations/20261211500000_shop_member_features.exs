defmodule Palee.Repo.Migrations.ShopMemberFeatures do
  @moduledoc """
  ADR-190, the member shop:

    * `shop_orders.pickup_code`: a short code the buyer shows at the desk,
      unique per business (existing orders get one); `reminded_at` records
      the pickup reminder.
    * `shop_stock_alerts`: «Ειδοποίησέ με» — a member asks to hear when a
      sold-out variant is back; `notified_at` is set when they were told (a
      new request clears it).
    * Notification types `shop_back_in_stock`, `shop_order_reminder`,
      `shop_order_cancelled`.
  """

  use Ecto.Migration

  @types ~w(shop_back_in_stock shop_order_reminder shop_order_cancelled)

  def up do
    alter table(:shop_orders) do
      add :pickup_code, :string
      add :reminded_at, :utc_datetime_usec
    end

    execute("""
    UPDATE shop_orders
    SET pickup_code = upper(substr(md5(id::text || random()::text), 1, 6))
    WHERE pickup_code IS NULL
    """)

    create unique_index(:shop_orders, [:organization_id, :pickup_code],
             name: :shop_orders_pickup_code_index,
             where: "pickup_code IS NOT NULL"
           )

    create table(:shop_stock_alerts, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :variant_id, :binary_id, null: false
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :notified_at, :utc_datetime_usec
      timestamps(type: :utc_datetime_usec)
    end

    execute("""
    ALTER TABLE shop_stock_alerts
    ADD CONSTRAINT shop_stock_alerts_variant_fkey
    FOREIGN KEY (variant_id, organization_id)
    REFERENCES shop_variants (id, organization_id) ON DELETE CASCADE
    """)

    create unique_index(:shop_stock_alerts, [:variant_id, :user_id],
             name: :shop_stock_alerts_variant_user_index
           )

    create index(:shop_stock_alerts, [:organization_id, :user_id])

    execute("""
    CREATE TRIGGER shop_stock_alerts_apply_tenant_context
    BEFORE INSERT OR UPDATE ON shop_stock_alerts
    FOR EACH ROW EXECUTE FUNCTION palee_apply_tenant_context()
    """)

    execute("""
    CREATE POLICY shop_stock_alerts_tenant_policy ON shop_stock_alerts
    USING (organization_id = NULLIF(current_setting('app.organization_id', true), '')::uuid)
    WITH CHECK (organization_id = NULLIF(current_setting('app.organization_id', true), '')::uuid)
    """)

    execute("ALTER TABLE shop_stock_alerts ENABLE ROW LEVEL SECURITY")
    execute("ALTER TABLE shop_stock_alerts FORCE ROW LEVEL SECURITY")

    rewrite_notification_types(&Enum.uniq(&1 ++ @types))
  end

  def down do
    execute(
      "DELETE FROM notifications WHERE type IN (#{Enum.map_join(@types, ", ", &"'#{&1}'")})"
    )

    rewrite_notification_types(&(&1 -- @types))
    drop table(:shop_stock_alerts)

    drop index(:shop_orders, [:organization_id, :pickup_code],
           name: :shop_orders_pickup_code_index
         )

    alter table(:shop_orders) do
      remove :pickup_code
      remove :reminded_at
    end
  end

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
