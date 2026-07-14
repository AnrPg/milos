defmodule MilosTraining.Repo.Migrations.ReformatFinanceInvoiceNumbers do
  use Ecto.Migration

  def up do
    execute("""
    CREATE SEQUENCE IF NOT EXISTS finance_invoice_number_seq
    AS bigint
    START WITH 1
    INCREMENT BY 1
    MINVALUE 1
    CACHE 1
    """)

    execute("""
    WITH numbered AS (
      SELECT
        fi.id,
        ROW_NUMBER() OVER (ORDER BY fi.inserted_at, fi.id) AS seq,
        TO_CHAR(fi.inserted_at AT TIME ZONE 'UTC', 'YYYYMMDDHH24MISS') AS inserted_at_utc,
        COALESCE(
          (
            SELECT LEFT(
              NULLIF(
                REGEXP_REPLACE(
                  UPPER(COALESCE(fil.package_code_snapshot, fil.package_family_snapshot, 'MANUAL')),
                  '[^A-Z0-9]+',
                  '',
                  'g'
                ),
                ''
              ),
              12
            )
            FROM finance_invoice_lines fil
            WHERE fil.finance_invoice_id = fi.id
            ORDER BY fil.inserted_at, fil.id
            LIMIT 1
          ),
          'MANUAL'
        ) AS package_segment
      FROM finance_invoices fi
    )
    UPDATE finance_invoices AS fi
    SET invoice_number =
      'INV-' ||
      LPAD(numbered.seq::text, 6, '0') ||
      '-' ||
      numbered.package_segment ||
      '-' ||
      numbered.inserted_at_utc
    FROM numbered
    WHERE fi.id = numbered.id
    """)

    execute("""
    SELECT setval(
      'finance_invoice_number_seq',
      GREATEST((SELECT COUNT(*) FROM finance_invoices), 1),
      (SELECT COUNT(*) > 0 FROM finance_invoices)
    )
    """)
  end

  def down do
    execute("DROP SEQUENCE IF EXISTS finance_invoice_number_seq")
  end
end
