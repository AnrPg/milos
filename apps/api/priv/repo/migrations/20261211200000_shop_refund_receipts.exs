defmodule Palee.Repo.Migrations.ShopRefundReceipts do
  @moduledoc """
  ADR-190: a member's shop refund gets its ADR-126 refund receipt even when the
  member holds no Finance membership. The receipt carries the revenue stream of
  the reversal it documents (copied by trigger), and only a shop receipt may
  name no membership.
  """

  use Ecto.Migration

  def up do
    alter table(:finance_refund_receipts) do
      add :revenue_stream, :text, null: false, default: "membership"
    end

    create constraint(:finance_refund_receipts, :finance_refund_receipts_revenue_stream_check,
             check: "revenue_stream IN ('membership', 'package', 'event', 'shop', 'other')"
           )

    execute("""
    UPDATE finance_refund_receipts receipt
    SET revenue_stream = reversal.revenue_stream
    FROM finance_payment_reversals reversal
    WHERE reversal.id = receipt.finance_payment_reversal_id
      AND reversal.revenue_stream <> receipt.revenue_stream
    """)

    execute("""
    CREATE OR REPLACE FUNCTION palee_finance_refund_receipt_stream() RETURNS trigger AS $$
    BEGIN
      SELECT reversal.revenue_stream INTO NEW.revenue_stream
      FROM finance_payment_reversals reversal
      WHERE reversal.id = NEW.finance_payment_reversal_id;

      NEW.revenue_stream := COALESCE(NEW.revenue_stream, 'membership');
      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql
    """)

    execute("""
    CREATE TRIGGER finance_refund_receipts_stream
    BEFORE INSERT ON finance_refund_receipts
    FOR EACH ROW EXECUTE FUNCTION palee_finance_refund_receipt_stream()
    """)

    execute("ALTER TABLE finance_refund_receipts ALTER COLUMN membership_id DROP NOT NULL")

    create constraint(:finance_refund_receipts, :finance_refund_receipts_member_or_shop_check,
             check: "membership_id IS NOT NULL OR revenue_stream = 'shop'"
           )
  end

  def down do
    drop constraint(:finance_refund_receipts, :finance_refund_receipts_member_or_shop_check)
    execute("ALTER TABLE finance_refund_receipts ALTER COLUMN membership_id SET NOT NULL")
    execute("DROP TRIGGER IF EXISTS finance_refund_receipts_stream ON finance_refund_receipts")
    execute("DROP FUNCTION IF EXISTS palee_finance_refund_receipt_stream()")
    drop constraint(:finance_refund_receipts, :finance_refund_receipts_revenue_stream_check)

    alter table(:finance_refund_receipts) do
      remove :revenue_stream
    end
  end
end
