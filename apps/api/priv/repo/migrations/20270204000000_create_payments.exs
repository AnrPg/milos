defmodule Palee.Repo.Migrations.CreatePayments do
  @moduledoc """
  ADR-246/247: online payments through the business's own payment provider
  account (Viva, Stripe, or the sandbox).

    * `payment_accounts` – one per organization: provider, environment and
      the encrypted credentials (DataCipher, ADR-161);
    * `payment_intents` – every attempt to take money online: a checkout the
      payer completes on the provider's page, or a charge of a saved card
      (merchant-initiated); also the outbox for fulfilment and retries;
    * `payment_methods` – saved cards: the provider's token only (never card
      data), the last 4 digits, and the payer's consent for later charges;
    * `payment_refunds` – money given back through the provider;
    * `payment_webhook_events` – what providers told us, once per event id.

  Membership and corporate payments learn the method `online`.
  """

  use Ecto.Migration

  @tables ~w(payment_accounts payment_methods payment_intents payment_refunds payment_webhook_events)
  @old_methods "'cash', 'bank_transfer', 'card_manual', 'other'"
  @new_methods "'cash', 'bank_transfer', 'card_manual', 'online', 'other'"

  def up do
    create table(:payment_accounts, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :provider, :string, null: false
      add :environment, :string, null: false
      add :status, :string, null: false, default: "active"
      add :settings, :map, null: false, default: %{}
      add :credentials, :binary
      add :last_error, :string, size: 500
      add :checked_at, :utc_datetime_usec
      add :updated_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:payment_accounts, [:organization_id])

    create unique_index(:payment_accounts, [:id, :organization_id],
             name: :payment_accounts_id_organization_index
           )

    create constraint(:payment_accounts, :payment_accounts_check,
             check: """
             provider IN ('sandbox', 'viva', 'stripe')
             AND environment IN ('test', 'live')
             AND status IN ('active', 'invalid', 'disabled')
             AND (provider = 'sandbox' OR credentials IS NOT NULL)
             AND (provider <> 'sandbox' OR environment = 'test')
             """
           )

    create table(:payment_methods, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :account_id, :binary_id, null: false
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :provider, :string, null: false
      add :token, :binary, null: false
      add :token_digest, :string, null: false
      add :brand, :string, size: 30
      add :last4, :string, size: 4
      add :exp_month, :integer
      add :exp_year, :integer
      add :status, :string, null: false, default: "active"
      add :autopay, :boolean, null: false, default: false
      add :consent_version, :string, null: false
      add :consent_text_hash, :string, null: false
      add :consented_at, :utc_datetime_usec, null: false
      add :consent_ip, :string, size: 64
      add :consent_user_agent, :string, size: 300
      add :max_amount_cents, :integer, null: false
      add :currency, :string, size: 3, null: false
      add :revoked_at, :utc_datetime_usec
      add :revoked_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      timestamps(type: :utc_datetime_usec)
    end

    execute("""
    ALTER TABLE payment_methods
    ADD CONSTRAINT payment_methods_account_fkey
    FOREIGN KEY (account_id, organization_id)
    REFERENCES payment_accounts (id, organization_id) ON DELETE CASCADE
    """)

    create unique_index(:payment_methods, [:id, :organization_id],
             name: :payment_methods_id_organization_index
           )

    create unique_index(:payment_methods, [:account_id, :token_digest])
    create index(:payment_methods, [:organization_id, :user_id])

    create index(:payment_methods, [:organization_id],
             where: "autopay AND status = 'active'",
             name: :payment_methods_autopay_index
           )

    create constraint(:payment_methods, :payment_methods_check,
             check: """
             provider IN ('sandbox', 'viva', 'stripe')
             AND status IN ('active', 'revoked', 'expired', 'failing')
             AND max_amount_cents > 0
             AND (last4 IS NULL OR last4 ~ '^[0-9]{4}$')
             AND (status <> 'revoked' OR revoked_at IS NOT NULL)
             """
           )

    create table(:payment_intents, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :account_id, :binary_id, null: false
      add :provider, :string, null: false
      add :environment, :string, null: false
      add :user_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :initiation, :string, null: false
      add :purpose_type, :string, null: false
      add :purpose_id, :binary_id, null: false
      add :amount_cents, :integer, null: false
      add :currency, :string, size: 3, null: false
      add :description, :string, size: 300, null: false
      add :status, :string, null: false
      add :idempotency_key, :string, size: 200, null: false
      add :provider_ref, :string, size: 200
      add :provider_transaction_id, :string, size: 200
      add :redirect_url, :string, size: 2000
      add :return_url, :string, size: 2000
      add :save_method, :boolean, null: false, default: false
      add :consent, :map
      add :payment_method_id, :binary_id
      add :attempts, :integer, null: false, default: 0
      add :next_attempt_at, :utc_datetime_usec
      add :claimed_at, :utc_datetime_usec
      add :expires_at, :utc_datetime_usec
      add :succeeded_at, :utc_datetime_usec
      add :failure_code, :string, size: 100
      add :failure_message, :string, size: 500
      add :card_brand, :string, size: 30
      add :card_last4, :string, size: 4
      add :refunded_cents, :integer, null: false, default: 0
      add :fulfilment_status, :string, null: false, default: "none"
      add :fulfilment_attempts, :integer, null: false, default: 0
      add :fulfilment_error, :string, size: 500
      add :fulfilled_at, :utc_datetime_usec
      add :finance_payment_id, :binary_id
      add :fiscal_document_id, :binary_id
      add :created_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      timestamps(type: :utc_datetime_usec)
    end

    execute("""
    ALTER TABLE payment_intents
    ADD CONSTRAINT payment_intents_account_fkey
    FOREIGN KEY (account_id, organization_id)
    REFERENCES payment_accounts (id, organization_id) ON DELETE RESTRICT
    """)

    execute("""
    ALTER TABLE payment_intents
    ADD CONSTRAINT payment_intents_method_fkey
    FOREIGN KEY (payment_method_id, organization_id)
    REFERENCES payment_methods (id, organization_id) ON DELETE RESTRICT
    """)

    create unique_index(:payment_intents, [:id, :organization_id],
             name: :payment_intents_id_organization_index
           )

    create unique_index(:payment_intents, [:organization_id, :idempotency_key])

    create unique_index(:payment_intents, [:provider, :provider_ref],
             where: "provider_ref IS NOT NULL",
             name: :payment_intents_provider_ref_index
           )

    create index(:payment_intents, [:organization_id, :purpose_type, :purpose_id])
    create index(:payment_intents, [:organization_id, :user_id, :inserted_at])

    create index(:payment_intents, [:next_attempt_at],
             where: "status IN ('scheduled', 'awaiting_payer', 'processing')",
             name: :payment_intents_due_index
           )

    create index(:payment_intents, [:organization_id],
             where: "fulfilment_status = 'pending'",
             name: :payment_intents_fulfilment_index
           )

    create constraint(:payment_intents, :payment_intents_check,
             check: """
             provider IN ('sandbox', 'viva', 'stripe')
             AND environment IN ('test', 'live')
             AND initiation IN ('payer', 'merchant')
             AND purpose_type IN ('finance_invoice', 'membership_package', 'shop_order', 'booking')
             AND status IN ('scheduled', 'awaiting_payer', 'processing', 'succeeded', 'failed',
                            'cancelled', 'expired')
             AND currency IN ('EUR', 'GBP', 'USD', 'CHF')
             AND amount_cents > 0
             AND refunded_cents >= 0 AND refunded_cents <= amount_cents
             AND attempts >= 0 AND fulfilment_attempts >= 0
             AND fulfilment_status IN ('none', 'pending', 'done', 'failed')
             AND (status <> 'succeeded' OR (succeeded_at IS NOT NULL AND provider_transaction_id IS NOT NULL))
             AND (initiation <> 'merchant' OR payment_method_id IS NOT NULL)
             AND (NOT save_method OR consent IS NOT NULL)
             """
           )

    create table(:payment_refunds, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :intent_id, :binary_id, null: false
      add :amount_cents, :integer, null: false
      add :currency, :string, size: 3, null: false
      add :status, :string, null: false, default: "pending"
      add :reason, :string, size: 300
      add :idempotency_key, :string, size: 200, null: false
      add :provider_ref, :string, size: 200
      add :failure_message, :string, size: 500
      add :finance_reversal_id, :binary_id
      add :created_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :completed_at, :utc_datetime_usec
      timestamps(type: :utc_datetime_usec)
    end

    execute("""
    ALTER TABLE payment_refunds
    ADD CONSTRAINT payment_refunds_intent_fkey
    FOREIGN KEY (intent_id, organization_id)
    REFERENCES payment_intents (id, organization_id) ON DELETE RESTRICT
    """)

    create unique_index(:payment_refunds, [:organization_id, :idempotency_key])
    create index(:payment_refunds, [:intent_id])

    create constraint(:payment_refunds, :payment_refunds_check,
             check: """
             amount_cents > 0 AND status IN ('pending', 'succeeded', 'failed')
             AND (status <> 'succeeded' OR completed_at IS NOT NULL)
             """
           )

    create table(:payment_webhook_events, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :account_id, :binary_id, null: false
      add :provider, :string, null: false
      add :event_id, :string, size: 200, null: false
      add :event_type, :string, size: 100
      add :reference, :string, size: 200
      add :status, :string, null: false, default: "received"
      add :error, :string, size: 500
      add :received_at, :utc_datetime_usec, null: false
      add :processed_at, :utc_datetime_usec
      timestamps(type: :utc_datetime_usec)
    end

    execute("""
    ALTER TABLE payment_webhook_events
    ADD CONSTRAINT payment_webhook_events_account_fkey
    FOREIGN KEY (account_id, organization_id)
    REFERENCES payment_accounts (id, organization_id) ON DELETE CASCADE
    """)

    create unique_index(:payment_webhook_events, [:account_id, :event_id])
    create index(:payment_webhook_events, [:organization_id, :received_at])

    create constraint(:payment_webhook_events, :payment_webhook_events_check,
             check: "status IN ('received', 'processed', 'ignored', 'failed')"
           )

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

    replace_method_check(@new_methods)
  end

  def down do
    replace_method_check(@old_methods)
    for table <- Enum.reverse(@tables), do: drop(table(String.to_atom(table)))
  end

  defp replace_method_check(methods) do
    for {table, name} <- [
          membership_payments: :membership_payments_method_check,
          finance_corporate_payments: :finance_corporate_payments_method
        ] do
      drop constraint(table, name)
      create constraint(table, name, check: "payment_method IN (#{methods})")
    end
  end
end
