defmodule MilosTraining.Repo.Migrations.FixFinanceAggregateMembershipLifecycle do
  use Ecto.Migration

  def up do
    recreate_view(active_filter())
  end

  def down do
    recreate_view("m.status = 'active'")
  end

  defp recreate_view(active_membership_filter) do
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
        COUNT(DISTINCT m.id) FILTER (WHERE #{active_membership_filter})::integer AS active_membership_count,
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
        0::integer AS membership_count,
        0::integer AS active_membership_count,
        0::integer AS expiring_membership_count,
        COALESCE(SUM(mp.amount_cents) FILTER (WHERE mp.payment_status = 'paid'), 0)::bigint AS paid_revenue_cents,
        COALESCE(SUM(mp.amount_cents) FILTER (WHERE mp.payment_status = 'pending'), 0)::bigint AS pending_revenue_cents,
        0::integer AS promotion_redemption_count,
        0::bigint AS promotion_discount_value,
        0::integer AS referral_signup_count,
        0::integer AS pending_referral_reward_count
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
        0::integer AS membership_count,
        0::integer AS active_membership_count,
        0::integer AS expiring_membership_count,
        0::bigint AS paid_revenue_cents,
        0::bigint AS pending_revenue_cents,
        COUNT(DISTINCT pr.id)::integer AS promotion_redemption_count,
        COALESCE(SUM(pr.discount_value_snapshot), 0)::bigint AS promotion_discount_value,
        0::integer AS referral_signup_count,
        0::integer AS pending_referral_reward_count
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
        0::integer AS membership_count,
        0::integer AS active_membership_count,
        0::integer AS expiring_membership_count,
        0::bigint AS paid_revenue_cents,
        0::bigint AS pending_revenue_cents,
        0::integer AS promotion_redemption_count,
        0::bigint AS promotion_discount_value,
        COUNT(DISTINCT re.id)::integer AS referral_signup_count,
        0::integer AS pending_referral_reward_count
      FROM referral_events re
      LEFT JOIN memberships m ON m.id = re.membership_id
      GROUP BY period_start, user_type_snapshot, package_code, package_family

      UNION ALL

      SELECT
        date_trunc('month', rr.inserted_at)::date AS period_start,
        COALESCE(m.user_type_snapshot, 'unknown') AS user_type_snapshot,
        'unassigned' AS package_code,
        'unassigned' AS package_family,
        0::integer AS membership_count,
        0::integer AS active_membership_count,
        0::integer AS expiring_membership_count,
        0::bigint AS paid_revenue_cents,
        0::bigint AS pending_revenue_cents,
        0::integer AS promotion_redemption_count,
        0::bigint AS promotion_discount_value,
        0::integer AS referral_signup_count,
        COUNT(DISTINCT rr.id) FILTER (WHERE rr.status = 'pending')::integer AS pending_referral_reward_count
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

  defp active_filter do
    """
    m.status IN ('active', 'trial', 'expiring', 'comped')
    AND (m.expires_on IS NULL OR m.expires_on >= timezone('utc', now())::date)
    """
  end
end
