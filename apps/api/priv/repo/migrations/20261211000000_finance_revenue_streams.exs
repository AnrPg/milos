defmodule Palee.Repo.Migrations.FinanceRevenueStreams do
  @moduledoc """
  ADR-190: a revenue stream and a source on Finance's money rows, so totals
  and exports can separate shop revenue from memberships, packages and
  events without reading line text.

  - `revenue_stream` (membership | package | event | shop | other) on
    `finance_invoices`, `finance_invoice_lines`, `membership_payments` and
    `finance_payment_reversals`. Existing rows are backfilled from what they
    already say: package lines are `membership`, manual event charges are
    `event`, other manual charges are `other`; invoices and payments are
    `membership`. New rows default to `membership`, so every existing writer
    keeps working unchanged.
  - `source_type` / `source_id` on lines, payments and reversals: the row
    that caused the money (`shop_order_line`, `shop_order`).
  - A reversal inherits the stream and source of the payment it reverses
    (trigger), so refunds keep the lineage whatever path records them.
  - A new manual-charge line takes its stream from `charge_category`
    (event -> event, otherwise other) unless the writer names one.
  - Shop sales to walk-in customers have no membership: `membership_id` /
    `user_id` become nullable on invoices, payments and reversals, and a
    check allows the gap for `revenue_stream = 'shop'` only.
  - `finance_invoices.fiscal_receipt_ref`: the legal receipt reference
    (Greek myDATA MARK or the register's receipt number) once one exists
    (TD-190).
  - `line_type` gains `shop_item`.
  """

  use Ecto.Migration

  @streams "'membership', 'package', 'event', 'shop', 'other'"

  def up do
    for table <- [
          :finance_invoices,
          :finance_invoice_lines,
          :membership_payments,
          :finance_payment_reversals
        ] do
      alter table(table) do
        add :revenue_stream, :string, null: false, default: "membership"
      end

      create constraint(table, :"#{table}_revenue_stream_check",
               check: "revenue_stream IN (#{@streams})"
             )

      create index(table, [:organization_id, :revenue_stream])
    end

    for table <- [:finance_invoice_lines, :membership_payments, :finance_payment_reversals] do
      alter table(table) do
        add :source_type, :string
        add :source_id, :binary_id
      end

      create index(table, [:source_type, :source_id], where: "source_id IS NOT NULL")
    end

    alter table(:finance_invoices) do
      add :fiscal_receipt_ref, :string
    end

    # One live payment per shop order: a retried capture cannot pay twice.
    create unique_index(:membership_payments, [:source_id],
             where: "source_type = 'shop_order' AND deleted_at IS NULL",
             name: :membership_payments_shop_order_index
           )

    execute("""
    UPDATE finance_invoice_lines
    SET revenue_stream = CASE
      WHEN line_type = 'manual_charge' AND charge_category = 'event' THEN 'event'
      WHEN line_type = 'manual_charge' THEN 'other'
      ELSE 'membership'
    END
    """)

    execute("ALTER TABLE finance_invoice_lines DROP CONSTRAINT finance_invoice_lines_type_check")

    execute("""
    ALTER TABLE finance_invoice_lines ADD CONSTRAINT finance_invoice_lines_type_check
    CHECK (line_type IN ('membership_package', 'manual_charge', 'discount', 'adjustment', 'shop_item'))
    """)

    execute("""
    CREATE OR REPLACE FUNCTION palee_finance_line_revenue_stream() RETURNS trigger AS $$
    BEGIN
      IF NEW.revenue_stream = 'membership' AND NEW.line_type = 'manual_charge' THEN
        NEW.revenue_stream := CASE WHEN NEW.charge_category = 'event' THEN 'event' ELSE 'other' END;
      END IF;
      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql
    """)

    execute("""
    CREATE TRIGGER finance_invoice_lines_revenue_stream
    BEFORE INSERT ON finance_invoice_lines
    FOR EACH ROW EXECUTE FUNCTION palee_finance_line_revenue_stream()
    """)

    execute("""
    CREATE OR REPLACE FUNCTION palee_finance_reversal_lineage() RETURNS trigger AS $$
    DECLARE
      payment record;
    BEGIN
      SELECT revenue_stream, source_type, source_id INTO payment
      FROM membership_payments WHERE id = NEW.membership_payment_id;

      IF FOUND THEN
        NEW.revenue_stream := payment.revenue_stream;
        NEW.source_type := COALESCE(NEW.source_type, payment.source_type);
        NEW.source_id := COALESCE(NEW.source_id, payment.source_id);
      END IF;

      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql
    """)

    execute("""
    CREATE TRIGGER finance_payment_reversals_lineage
    BEFORE INSERT ON finance_payment_reversals
    FOR EACH ROW EXECUTE FUNCTION palee_finance_reversal_lineage()
    """)

    for {table, columns} <- [
          finance_invoices: [:membership_id, :user_id],
          membership_payments: [:membership_id],
          finance_payment_reversals: [:membership_id, :user_id]
        ] do
      for column <- columns do
        execute("ALTER TABLE #{table} ALTER COLUMN #{column} DROP NOT NULL")
      end

      check = Enum.map_join(columns, " AND ", &"#{&1} IS NOT NULL")

      create constraint(table, :"#{table}_member_or_shop_check",
               check: "(#{check}) OR revenue_stream = 'shop'"
             )
    end
  end

  def down do
    for {table, columns} <- [
          finance_invoices: [:membership_id, :user_id],
          membership_payments: [:membership_id],
          finance_payment_reversals: [:membership_id, :user_id]
        ] do
      drop constraint(table, :"#{table}_member_or_shop_check")

      for column <- columns,
          do: execute("ALTER TABLE #{table} ALTER COLUMN #{column} SET NOT NULL")
    end

    execute(
      "DROP TRIGGER IF EXISTS finance_payment_reversals_lineage ON finance_payment_reversals"
    )

    execute("DROP FUNCTION IF EXISTS palee_finance_reversal_lineage()")

    execute(
      "DROP TRIGGER IF EXISTS finance_invoice_lines_revenue_stream ON finance_invoice_lines"
    )

    execute("DROP FUNCTION IF EXISTS palee_finance_line_revenue_stream()")

    execute("ALTER TABLE finance_invoice_lines DROP CONSTRAINT finance_invoice_lines_type_check")

    execute("""
    ALTER TABLE finance_invoice_lines ADD CONSTRAINT finance_invoice_lines_type_check
    CHECK (line_type IN ('membership_package', 'manual_charge', 'discount', 'adjustment'))
    """)

    drop index(:membership_payments, [:source_id], name: :membership_payments_shop_order_index)

    alter table(:finance_invoices) do
      remove :fiscal_receipt_ref
    end

    for table <- [:finance_invoice_lines, :membership_payments, :finance_payment_reversals] do
      alter table(table) do
        remove :source_type
        remove :source_id
      end
    end

    for table <- [
          :finance_invoices,
          :finance_invoice_lines,
          :membership_payments,
          :finance_payment_reversals
        ] do
      drop constraint(table, :"#{table}_revenue_stream_check")

      alter table(table) do
        remove :revenue_stream
      end
    end
  end
end
