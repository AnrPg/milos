defmodule MilosTraining.Repo.Migrations.HardenFinanceDiscountAggregates do
  use Ecto.Migration

  def up do
    recreate_view()
  end

  def down do
    raise "finance aggregate discount hardening is not automatically reversible"
  end

  defp recreate_view do
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
        0::integer AS promotion_percent_redemption_count,
        0::integer AS promotion_fixed_amount_redemption_count,
        0::integer AS promotion_free_period_redemption_count,
        0::integer AS promotion_manual_redemption_count,
        0::bigint AS promotion_realized_discount_cents,
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
        date_trunc('month', mp.paid_on::timestamp)::date,
        COALESCE(m.user_type_snapshot, 'unknown'),
        COALESCE(mps.package_code_snapshot, 'unassigned'),
        COALESCE(mps.package_family_snapshot, 'unassigned'),
        0::integer, 0::integer, 0::integer,
        COALESCE(SUM(mp.amount_cents) FILTER (WHERE mp.payment_status = 'paid'), 0)::bigint,
        COALESCE(SUM(mp.amount_cents) FILTER (WHERE mp.payment_status = 'pending'), 0)::bigint,
        0::integer, 0::integer, 0::integer, 0::integer, 0::integer, 0::bigint,
        0::integer, 0::integer, 0::bigint, 0::bigint, 0::bigint
      FROM membership_payments mp
      JOIN memberships m ON m.id = mp.membership_id
      LEFT JOIN membership_package_subscriptions mps ON mps.id = mp.membership_package_subscription_id
      GROUP BY 1, 2, 3, 4

      UNION ALL

      SELECT
        date_trunc('month', pr.redeemed_at)::date,
        COALESCE(m.user_type_snapshot, 'unknown'),
        COALESCE(mps.package_code_snapshot, 'unassigned'),
        COALESCE(mps.package_family_snapshot, 'unassigned'),
        0::integer, 0::integer, 0::integer, 0::bigint, 0::bigint,
        COUNT(DISTINCT pr.id)::integer,
        COUNT(DISTINCT pr.id) FILTER (WHERE pr.discount_type_snapshot = 'percent')::integer,
        COUNT(DISTINCT pr.id) FILTER (WHERE pr.discount_type_snapshot = 'fixed_amount')::integer,
        COUNT(DISTINCT pr.id) FILTER (WHERE pr.discount_type_snapshot = 'free_period')::integer,
        COUNT(DISTINCT pr.id) FILTER (WHERE pr.discount_type_snapshot = 'manual')::integer,
        COALESCE(SUM(
          CASE
            WHEN pr.params ? 'realized_discount_cents'
              AND (pr.params->>'realized_discount_cents') ~ '^[0-9]+$'
            THEN (pr.params->>'realized_discount_cents')::bigint
            ELSE 0
          END
        ), 0)::bigint,
        0::integer, 0::integer, 0::bigint, 0::bigint, 0::bigint
      FROM promotion_redemptions pr
      JOIN memberships m ON m.id = pr.membership_id
      LEFT JOIN membership_package_subscriptions mps ON mps.id = pr.membership_package_subscription_id
      GROUP BY 1, 2, 3, 4

      UNION ALL

      SELECT
        date_trunc('month', re.inserted_at)::date,
        COALESCE(m.user_type_snapshot, 'unknown'),
        'unassigned', 'unassigned',
        0::integer, 0::integer, 0::integer, 0::bigint, 0::bigint,
        0::integer, 0::integer, 0::integer, 0::integer, 0::integer, 0::bigint,
        COUNT(DISTINCT re.id)::integer,
        0::integer, 0::bigint, 0::bigint, 0::bigint
      FROM referral_events re
      LEFT JOIN memberships m ON m.id = re.membership_id
      GROUP BY 1, 2, 3, 4

      UNION ALL

      SELECT
        date_trunc('month', rr.inserted_at)::date,
        COALESCE(m.user_type_snapshot, 'unknown'),
        'unassigned', 'unassigned',
        0::integer, 0::integer, 0::integer, 0::bigint, 0::bigint,
        0::integer, 0::integer, 0::integer, 0::integer, 0::integer, 0::bigint,
        0::integer,
        COUNT(DISTINCT rr.id) FILTER (WHERE rr.status = 'pending')::integer,
        0::bigint, 0::bigint, 0::bigint
      FROM referral_rewards rr
      LEFT JOIN memberships m ON m.id = rr.membership_id
      GROUP BY 1, 2, 3, 4

      UNION ALL

      SELECT
        date_trunc('month', fcle.occurred_at)::date,
        COALESCE(m.user_type_snapshot, 'unknown'),
        COALESCE(mps.package_code_snapshot, 'unassigned'),
        COALESCE(mps.package_family_snapshot, 'unassigned'),
        0::integer, 0::integer, 0::integer, 0::bigint, 0::bigint,
        0::integer, 0::integer, 0::integer, 0::integer, 0::integer, 0::bigint,
        0::integer, 0::integer,
        COALESCE(SUM(fcle.amount_cents) FILTER (WHERE fcle.amount_cents > 0), 0)::bigint,
        ABS(COALESCE(SUM(fcle.amount_cents) FILTER (WHERE fcle.amount_cents < 0), 0))::bigint,
        COALESCE(SUM(fcle.amount_cents), 0)::bigint
      FROM finance_credit_ledger_entries fcle
      JOIN memberships m ON m.id = fcle.membership_id
      LEFT JOIN membership_payments mp ON mp.id = fcle.membership_payment_id
      LEFT JOIN membership_package_subscriptions mps ON mps.id = mp.membership_package_subscription_id
      GROUP BY 1, 2, 3, 4
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
      SUM(promotion_percent_redemption_count)::integer AS promotion_percent_redemption_count,
      SUM(promotion_fixed_amount_redemption_count)::integer AS promotion_fixed_amount_redemption_count,
      SUM(promotion_free_period_redemption_count)::integer AS promotion_free_period_redemption_count,
      SUM(promotion_manual_redemption_count)::integer AS promotion_manual_redemption_count,
      SUM(promotion_realized_discount_cents)::bigint AS promotion_realized_discount_cents,
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
end
