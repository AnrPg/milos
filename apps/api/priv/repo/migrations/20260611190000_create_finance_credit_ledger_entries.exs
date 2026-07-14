defmodule MilosTraining.Repo.Migrations.CreateFinanceCreditLedgerEntries do
  use Ecto.Migration

  def up do
    create table(:finance_credit_ledger_entries, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :membership_id, references(:memberships, type: :binary_id, on_delete: :delete_all),
        null: false

      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      add :membership_payment_id,
          references(:membership_payments, type: :binary_id, on_delete: :nilify_all)

      add :referral_reward_id,
          references(:referral_rewards, type: :binary_id, on_delete: :nilify_all)

      add :promotion_redemption_id,
          references(:promotion_redemptions, type: :binary_id, on_delete: :nilify_all)

      add :source_type, :string, null: false
      add :entry_type, :string, null: false
      add :amount_cents, :integer, null: false
      add :currency, :string, null: false, default: "EUR"
      add :occurred_on, :date, null: false
      add :occurred_at, :utc_datetime_usec, null: false
      add :description, :text
      add :created_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :idempotency_key, :string
      add :params, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create index(:finance_credit_ledger_entries, [:membership_id, :occurred_at])
    create index(:finance_credit_ledger_entries, [:user_id, :occurred_at])
    create index(:finance_credit_ledger_entries, [:membership_payment_id])
    create index(:finance_credit_ledger_entries, [:referral_reward_id])
    create index(:finance_credit_ledger_entries, [:promotion_redemption_id])
    create index(:finance_credit_ledger_entries, [:source_type])
    create index(:finance_credit_ledger_entries, [:entry_type])
    create unique_index(:finance_credit_ledger_entries, [:idempotency_key])

    create constraint(:finance_credit_ledger_entries, :finance_credit_entries_source_type_check,
             check:
               "source_type IN ('referral_reward', 'manual_credit', 'promo_credit', 'payment_application', 'reversal', 'invoice_offset')"
           )

    create constraint(:finance_credit_ledger_entries, :finance_credit_entries_entry_type_check,
             check: "entry_type IN ('grant', 'application', 'reversal', 'invoice_offset')"
           )

    create constraint(:finance_credit_ledger_entries, :finance_credit_entries_amount_check,
             check: "amount_cents <> 0"
           )

    recreate_finance_aggregates()
  end

  def down do
    execute("DROP MATERIALIZED VIEW IF EXISTS finance_aggregates")
    drop table(:finance_credit_ledger_entries)
    recreate_previous_finance_aggregates()
  end

  defp recreate_finance_aggregates do
    execute("DROP MATERIALIZED VIEW IF EXISTS finance_aggregates")

    execute("""
    CREATE MATERIALIZED VIEW finance_aggregates AS
    WITH aggregate_facts AS (
      SELECT
        date_trunc('month', m.inserted_at)::date AS period_start,
        COALESCE(m.user_type_snapshot, 'unknown') AS user_type_snapshot,
        COALESCE(mps.package_code_snapshot, 'unassigned') AS package_code,
        COALESCE(mps.package_family_snapshot, 'unassigned') AS package_family,
        COUNT(DISTINCT m.id)::integer AS membership_count,
        COUNT(DISTINCT m.id) FILTER (
          WHERE m.status IN ('active', 'trial', 'expiring', 'comped')
            AND (m.expires_on IS NULL OR m.expires_on >= timezone('utc', now())::date)
        )::integer AS active_membership_count,
        COUNT(DISTINCT m.id) FILTER (
          WHERE m.expires_on IS NOT NULL
            AND m.expires_on >= timezone('utc', now())::date
            AND m.expires_on <= (timezone('utc', now())::date + interval '30 days')
            AND m.status IN ('active', 'expiring', 'trial')
        )::integer AS expiring_membership_count,
        0::bigint AS paid_revenue_cents,
        0::bigint AS pending_revenue_cents,
        0::integer AS promotion_redemption_count,
        0::bigint AS promotion_discount_value,
        0::integer AS referral_signup_count,
        0::integer AS pending_referral_reward_count,
        0::bigint AS credit_granted_cents,
        0::bigint AS credit_applied_cents,
        0::bigint AS credit_balance_cents
      FROM memberships m
      LEFT JOIN membership_package_subscriptions mps ON mps.membership_id = m.id
      GROUP BY period_start, user_type_snapshot, package_code, package_family

      UNION ALL

      SELECT
        date_trunc('month', mp.paid_on::timestamp)::date AS period_start,
        COALESCE(m.user_type_snapshot, 'unknown') AS user_type_snapshot,
        COALESCE(mps.package_code_snapshot, 'unassigned') AS package_code,
        COALESCE(mps.package_family_snapshot, 'unassigned') AS package_family,
        0::integer, 0::integer, 0::integer,
        COALESCE(SUM(mp.amount_cents) FILTER (WHERE mp.payment_status = 'paid'), 0)::bigint,
        COALESCE(SUM(mp.amount_cents) FILTER (WHERE mp.payment_status = 'pending'), 0)::bigint,
        0::integer, 0::bigint, 0::integer, 0::integer,
        0::bigint, 0::bigint, 0::bigint
      FROM membership_payments mp
      JOIN memberships m ON m.id = mp.membership_id
      LEFT JOIN membership_package_subscriptions mps ON mps.id = mp.membership_package_subscription_id
      GROUP BY period_start, user_type_snapshot, package_code, package_family

      UNION ALL

      SELECT
        date_trunc('month', pr.redeemed_at)::date AS period_start,
        COALESCE(m.user_type_snapshot, 'unknown') AS user_type_snapshot,
        COALESCE(mps.package_code_snapshot, 'unassigned') AS package_code,
        COALESCE(mps.package_family_snapshot, 'unassigned') AS package_family,
        0::integer, 0::integer, 0::integer,
        0::bigint, 0::bigint,
        COUNT(DISTINCT pr.id)::integer,
        COALESCE(SUM(pr.discount_value_snapshot), 0)::bigint,
        0::integer, 0::integer,
        0::bigint, 0::bigint, 0::bigint
      FROM promotion_redemptions pr
      JOIN memberships m ON m.id = pr.membership_id
      LEFT JOIN membership_package_subscriptions mps ON mps.id = pr.membership_package_subscription_id
      GROUP BY period_start, user_type_snapshot, package_code, package_family

      UNION ALL

      SELECT
        date_trunc('month', re.inserted_at)::date AS period_start,
        COALESCE(m.user_type_snapshot, 'unknown') AS user_type_snapshot,
        'unassigned' AS package_code,
        'unassigned' AS package_family,
        0::integer, 0::integer, 0::integer,
        0::bigint, 0::bigint, 0::integer, 0::bigint,
        COUNT(DISTINCT re.id)::integer,
        0::integer,
        0::bigint, 0::bigint, 0::bigint
      FROM referral_events re
      LEFT JOIN memberships m ON m.id = re.membership_id
      GROUP BY period_start, user_type_snapshot, package_code, package_family

      UNION ALL

      SELECT
        date_trunc('month', rr.inserted_at)::date AS period_start,
        COALESCE(m.user_type_snapshot, 'unknown') AS user_type_snapshot,
        'unassigned' AS package_code,
        'unassigned' AS package_family,
        0::integer, 0::integer, 0::integer,
        0::bigint, 0::bigint, 0::integer, 0::bigint, 0::integer,
        COUNT(DISTINCT rr.id) FILTER (WHERE rr.status = 'pending')::integer,
        0::bigint, 0::bigint, 0::bigint
      FROM referral_rewards rr
      LEFT JOIN memberships m ON m.id = rr.membership_id
      GROUP BY period_start, user_type_snapshot, package_code, package_family

      UNION ALL

      SELECT
        date_trunc('month', fcle.occurred_at)::date AS period_start,
        COALESCE(m.user_type_snapshot, 'unknown') AS user_type_snapshot,
        COALESCE(mps.package_code_snapshot, 'unassigned') AS package_code,
        COALESCE(mps.package_family_snapshot, 'unassigned') AS package_family,
        0::integer, 0::integer, 0::integer,
        0::bigint, 0::bigint, 0::integer, 0::bigint, 0::integer, 0::integer,
        COALESCE(SUM(fcle.amount_cents) FILTER (WHERE fcle.amount_cents > 0), 0)::bigint,
        ABS(COALESCE(SUM(fcle.amount_cents) FILTER (WHERE fcle.amount_cents < 0), 0))::bigint,
        COALESCE(SUM(fcle.amount_cents), 0)::bigint
      FROM finance_credit_ledger_entries fcle
      JOIN memberships m ON m.id = fcle.membership_id
      LEFT JOIN membership_payments mp ON mp.id = fcle.membership_payment_id
      LEFT JOIN membership_package_subscriptions mps ON mps.id = mp.membership_package_subscription_id
      GROUP BY period_start, user_type_snapshot, package_code, package_family
    )
    SELECT
      period_start,
      user_type_snapshot,
      package_code,
      package_family,
      SUM(membership_count)::integer AS membership_count,
      SUM(active_membership_count)::integer AS active_membership_count,
      SUM(expiring_membership_count)::integer AS expiring_membership_count,
      SUM(paid_revenue_cents)::bigint AS paid_revenue_cents,
      SUM(pending_revenue_cents)::bigint AS pending_revenue_cents,
      SUM(promotion_redemption_count)::integer AS promotion_redemption_count,
      SUM(promotion_discount_value)::bigint AS promotion_discount_value,
      SUM(referral_signup_count)::integer AS referral_signup_count,
      SUM(pending_referral_reward_count)::integer AS pending_referral_reward_count,
      SUM(credit_granted_cents)::bigint AS credit_granted_cents,
      SUM(credit_applied_cents)::bigint AS credit_applied_cents,
      SUM(credit_balance_cents)::bigint AS credit_balance_cents
    FROM aggregate_facts
    WHERE period_start IS NOT NULL
    GROUP BY period_start, user_type_snapshot, package_code, package_family
    WITH NO DATA
    """)

    execute("""
    CREATE UNIQUE INDEX finance_aggregates_period_user_type_package_index
    ON finance_aggregates (period_start, user_type_snapshot, package_code, package_family)
    """)

    execute("REFRESH MATERIALIZED VIEW finance_aggregates")
  end

  defp recreate_previous_finance_aggregates do
    execute("""
    CREATE MATERIALIZED VIEW finance_aggregates AS
    WITH aggregate_facts AS (
      SELECT
        date_trunc('month', m.inserted_at)::date AS period_start,
        COALESCE(m.user_type_snapshot, 'unknown') AS user_type_snapshot,
        COALESCE(mps.package_code_snapshot, 'unassigned') AS package_code,
        COALESCE(mps.package_family_snapshot, 'unassigned') AS package_family,
        COUNT(DISTINCT m.id)::integer AS membership_count,
        COUNT(DISTINCT m.id) FILTER (WHERE m.status = 'active')::integer AS active_membership_count,
        COUNT(DISTINCT m.id) FILTER (
          WHERE m.expires_on IS NOT NULL
            AND m.expires_on >= timezone('utc', now())::date
            AND m.expires_on <= (timezone('utc', now())::date + interval '30 days')
            AND m.status IN ('active', 'expiring', 'trial')
        )::integer AS expiring_membership_count,
        0::bigint AS paid_revenue_cents,
        0::bigint AS pending_revenue_cents,
        0::integer AS promotion_redemption_count,
        0::bigint AS promotion_discount_value,
        0::integer AS referral_signup_count,
        0::integer AS pending_referral_reward_count
      FROM memberships m
      LEFT JOIN membership_package_subscriptions mps ON mps.membership_id = m.id
      GROUP BY period_start, user_type_snapshot, package_code, package_family

      UNION ALL

      SELECT
        date_trunc('month', mp.paid_on::timestamp)::date AS period_start,
        COALESCE(m.user_type_snapshot, 'unknown') AS user_type_snapshot,
        COALESCE(mps.package_code_snapshot, 'unassigned') AS package_code,
        COALESCE(mps.package_family_snapshot, 'unassigned') AS package_family,
        0::integer, 0::integer, 0::integer,
        COALESCE(SUM(mp.amount_cents) FILTER (WHERE mp.payment_status = 'paid'), 0)::bigint,
        COALESCE(SUM(mp.amount_cents) FILTER (WHERE mp.payment_status = 'pending'), 0)::bigint,
        0::integer, 0::bigint, 0::integer, 0::integer
      FROM membership_payments mp
      JOIN memberships m ON m.id = mp.membership_id
      LEFT JOIN membership_package_subscriptions mps ON mps.id = mp.membership_package_subscription_id
      GROUP BY period_start, user_type_snapshot, package_code, package_family

      UNION ALL

      SELECT
        date_trunc('month', pr.redeemed_at)::date AS period_start,
        COALESCE(m.user_type_snapshot, 'unknown') AS user_type_snapshot,
        COALESCE(mps.package_code_snapshot, 'unassigned') AS package_code,
        COALESCE(mps.package_family_snapshot, 'unassigned') AS package_family,
        0::integer, 0::integer, 0::integer,
        0::bigint, 0::bigint,
        COUNT(DISTINCT pr.id)::integer,
        COALESCE(SUM(pr.discount_value_snapshot), 0)::bigint,
        0::integer, 0::integer
      FROM promotion_redemptions pr
      JOIN memberships m ON m.id = pr.membership_id
      LEFT JOIN membership_package_subscriptions mps ON mps.id = pr.membership_package_subscription_id
      GROUP BY period_start, user_type_snapshot, package_code, package_family

      UNION ALL

      SELECT
        date_trunc('month', re.inserted_at)::date AS period_start,
        COALESCE(m.user_type_snapshot, 'unknown') AS user_type_snapshot,
        'unassigned' AS package_code,
        'unassigned' AS package_family,
        0::integer, 0::integer, 0::integer,
        0::bigint, 0::bigint, 0::integer, 0::bigint,
        COUNT(DISTINCT re.id)::integer,
        0::integer
      FROM referral_events re
      LEFT JOIN memberships m ON m.id = re.membership_id
      GROUP BY period_start, user_type_snapshot, package_code, package_family

      UNION ALL

      SELECT
        date_trunc('month', rr.inserted_at)::date AS period_start,
        COALESCE(m.user_type_snapshot, 'unknown') AS user_type_snapshot,
        'unassigned' AS package_code,
        'unassigned' AS package_family,
        0::integer, 0::integer, 0::integer,
        0::bigint, 0::bigint, 0::integer, 0::bigint, 0::integer,
        COUNT(DISTINCT rr.id) FILTER (WHERE rr.status = 'pending')::integer
      FROM referral_rewards rr
      LEFT JOIN memberships m ON m.id = rr.membership_id
      GROUP BY period_start, user_type_snapshot, package_code, package_family
    )
    SELECT
      period_start,
      user_type_snapshot,
      package_code,
      package_family,
      SUM(membership_count)::integer AS membership_count,
      SUM(active_membership_count)::integer AS active_membership_count,
      SUM(expiring_membership_count)::integer AS expiring_membership_count,
      SUM(paid_revenue_cents)::bigint AS paid_revenue_cents,
      SUM(pending_revenue_cents)::bigint AS pending_revenue_cents,
      SUM(promotion_redemption_count)::integer AS promotion_redemption_count,
      SUM(promotion_discount_value)::bigint AS promotion_discount_value,
      SUM(referral_signup_count)::integer AS referral_signup_count,
      SUM(pending_referral_reward_count)::integer AS pending_referral_reward_count
    FROM aggregate_facts
    WHERE period_start IS NOT NULL
    GROUP BY period_start, user_type_snapshot, package_code, package_family
    WITH NO DATA
    """)

    execute("""
    CREATE UNIQUE INDEX finance_aggregates_period_user_type_package_index
    ON finance_aggregates (period_start, user_type_snapshot, package_code, package_family)
    """)

    execute("REFRESH MATERIALIZED VIEW finance_aggregates")
  end
end
