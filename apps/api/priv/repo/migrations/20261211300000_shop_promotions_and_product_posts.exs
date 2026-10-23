defmodule Palee.Repo.Migrations.ShopPromotionsAndProductPosts do
  @moduledoc """
  ADR-190 «Προώθηση»: staff promote a product with a club post whose
  attachment is the product (`attachment_type = 'product'`), optionally with a
  product-scoped promotion code.

    * `shop_promotion_codes`: a code of one product — percent off, or an
      amount off each unit — with an optional end and redemption cap, and the
      post that announced it. Redemptions are the non-cancelled orders that
      used it (`shop_orders.promotion_code_id`), counted under a row lock.
    * `community_posts.attachment_type` may be `product`.
  """

  use Ecto.Migration

  @attachments_before ~w(training_log_entry workout_execution pr event)

  def up do
    create table(:shop_promotion_codes, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :product_id, :binary_id, null: false
      add :code, :string, null: false
      add :discount_percent, :integer
      add :discount_cents, :integer
      add :max_redemptions, :integer
      add :starts_at, :utc_datetime_usec
      add :ends_at, :utc_datetime_usec
      add :active, :boolean, null: false, default: true
      add :post_id, :binary_id
      add :created_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:shop_promotion_codes, [:id, :organization_id],
             name: :shop_promotion_codes_id_organization_index
           )

    create unique_index(:shop_promotion_codes, [:organization_id, :code],
             name: :shop_promotion_codes_organization_code_index
           )

    create index(:shop_promotion_codes, [:organization_id, :product_id])

    execute("""
    ALTER TABLE shop_promotion_codes
    ADD CONSTRAINT shop_promotion_codes_product_fkey
    FOREIGN KEY (product_id, organization_id)
    REFERENCES shop_products (id, organization_id) ON DELETE CASCADE
    """)

    execute("""
    ALTER TABLE shop_promotion_codes
    ADD CONSTRAINT shop_promotion_codes_post_fkey
    FOREIGN KEY (post_id, organization_id)
    REFERENCES community_posts (id, organization_id) ON DELETE SET NULL (post_id)
    """)

    create constraint(:shop_promotion_codes, :shop_promotion_codes_discount_check,
             check:
               "(discount_percent IS NOT NULL AND discount_cents IS NULL AND discount_percent BETWEEN 1 AND 100) OR " <>
                 "(discount_cents IS NOT NULL AND discount_percent IS NULL AND discount_cents > 0)"
           )

    create constraint(:shop_promotion_codes, :shop_promotion_codes_code_check,
             check: "code ~ '^[A-Z0-9_-]{3,32}$'"
           )

    create constraint(:shop_promotion_codes, :shop_promotion_codes_window_check,
             check:
               "(max_redemptions IS NULL OR max_redemptions > 0) AND (starts_at IS NULL OR ends_at IS NULL OR starts_at < ends_at)"
           )

    execute("""
    CREATE TRIGGER shop_promotion_codes_apply_tenant_context
    BEFORE INSERT OR UPDATE ON shop_promotion_codes
    FOR EACH ROW EXECUTE FUNCTION palee_apply_tenant_context()
    """)

    execute("""
    CREATE POLICY shop_promotion_codes_tenant_policy ON shop_promotion_codes
    USING (organization_id = NULLIF(current_setting('app.organization_id', true), '')::uuid)
    WITH CHECK (organization_id = NULLIF(current_setting('app.organization_id', true), '')::uuid)
    """)

    execute("ALTER TABLE shop_promotion_codes ENABLE ROW LEVEL SECURITY")
    execute("ALTER TABLE shop_promotion_codes FORCE ROW LEVEL SECURITY")

    alter table(:shop_orders) do
      add :promotion_code_id, :binary_id
    end

    execute("""
    ALTER TABLE shop_orders
    ADD CONSTRAINT shop_orders_promotion_code_fkey
    FOREIGN KEY (promotion_code_id, organization_id)
    REFERENCES shop_promotion_codes (id, organization_id)
    """)

    create index(:shop_orders, [:promotion_code_id], where: "promotion_code_id IS NOT NULL")

    replace_attachment_check(@attachments_before ++ ["product"])
  end

  def down do
    execute("DELETE FROM community_posts WHERE attachment_type = 'product'")
    replace_attachment_check(@attachments_before)

    alter table(:shop_orders) do
      remove :promotion_code_id
    end

    drop table(:shop_promotion_codes)
  end

  defp replace_attachment_check(types) do
    execute("ALTER TABLE community_posts DROP CONSTRAINT community_posts_attachment_check")

    create constraint(:community_posts, :community_posts_attachment_check,
             check:
               "(attachment_type IS NULL AND attachment_id IS NULL AND attachment IS NULL) OR " <>
                 "(attachment_type IN (#{Enum.map_join(types, ", ", &"'#{&1}'")}) AND attachment_id IS NOT NULL AND attachment IS NOT NULL)"
           )
  end
end
