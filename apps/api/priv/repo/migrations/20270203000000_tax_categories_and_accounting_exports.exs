defmodule Palee.Repo.Migrations.TaxCategoriesAndAccountingExports do
  @moduledoc """
  ADR-244 and ADR-245.

    * `tax_category` and `exemption_reason` on what a gym sells: membership
      packages, shop products (the default of their variants) and shop
      variants (an override; `tax_class` stays as the deprecated name and is
      copied into `tax_category`). NULL means `standard` on a package or a
      product and "as the product" on a variant;
    * bank details on the fiscal business identity (`iban`, `qr_iban`) for
      the Swiss QR-bill and the payment details printed on invoices;
    * `fiscal_sales_tax_rates` – US sales tax rates the gym keeps by state and
      ZIP code (the `RateTable` sales tax calculator);
    * `fiscal_export_settings` – per accounting export format, the gym's
      options (DATEV chart of accounts, account numbers, tax codes).
  """

  use Ecto.Migration

  @categories "'standard', 'reduced', 'second_reduced', 'super_reduced', 'special', 'zero', 'exempt', 'sales_tax'"
  @tables ~w(fiscal_sales_tax_rates fiscal_export_settings)

  def up do
    for table <- [:membership_packages, :shop_products, :shop_variants] do
      alter table(table) do
        add :tax_category, :string, size: 20
        add :exemption_reason, :string, size: 300
      end

      create constraint(table, :"#{table}_tax_category_check",
               check: """
               (tax_category IS NULL OR tax_category IN (#{@categories}))
               AND (tax_category IS DISTINCT FROM 'exempt' OR exemption_reason IS NOT NULL)
               """
             )
    end

    execute("UPDATE shop_variants SET tax_category = tax_class WHERE tax_class IS NOT NULL")

    execute("""
    UPDATE shop_variants SET exemption_reason = 'exempt'
    WHERE tax_category = 'exempt' AND exemption_reason IS NULL
    """)

    alter table(:fiscal_business_identities) do
      add :iban, :string, size: 34
      add :qr_iban, :string, size: 34
    end

    create table(:fiscal_sales_tax_rates, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :state, :string, size: 2, null: false
      add :zip, :string, size: 5
      add :rate_bp, :integer, null: false
      add :label, :string, size: 120
      add :updated_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      timestamps(type: :utc_datetime_usec)
    end

    execute("""
    CREATE UNIQUE INDEX fiscal_sales_tax_rates_place_index
    ON fiscal_sales_tax_rates (organization_id, state, COALESCE(zip, ''))
    """)

    create constraint(:fiscal_sales_tax_rates, :fiscal_sales_tax_rates_check,
             check: """
             state ~ '^[A-Z]{2}$' AND (zip IS NULL OR zip ~ '^[0-9]{5}$')
             AND rate_bp >= 0 AND rate_bp < 10000
             """
           )

    create table(:fiscal_export_settings, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :format, :string, size: 30, null: false
      add :options, :map, null: false, default: %{}
      add :updated_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:fiscal_export_settings, [:organization_id, :format])

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
  end

  def down do
    for table <- Enum.reverse(@tables), do: drop(table(String.to_atom(table)))

    alter table(:fiscal_business_identities) do
      remove :iban
      remove :qr_iban
    end

    for table <- [:membership_packages, :shop_products, :shop_variants] do
      drop constraint(table, :"#{table}_tax_category_check")

      alter table(table) do
        remove :tax_category
        remove :exemption_reason
      end
    end
  end
end
