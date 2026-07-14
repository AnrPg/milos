defmodule MilosTraining.Repo.Migrations.CreatePhase8FinanceAnalyticsFoundations do
  use Ecto.Migration

  def up do
    create table(:membership_packages, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :code, :string, null: false
      add :name, :string, null: false
      add :description, :text
      add :family, :string, null: false
      add :billing_period, :string, null: false
      add :base_price_cents, :integer, null: false, default: 0
      add :currency, :string, null: false, default: "EUR"
      add :tags, {:array, :string}, null: false, default: []
      add :params, :map, null: false, default: %{}
      add :active, :boolean, null: false, default: true

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:membership_packages, [:code])
    create index(:membership_packages, [:family])
    create index(:membership_packages, [:billing_period])
    create index(:membership_packages, [:active])

    create constraint(:membership_packages, :membership_packages_price_check,
             check: "base_price_cents >= 0"
           )

    create table(:memberships, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :user_type_snapshot, :string, null: false
      add :status, :string, null: false, default: "trial"
      add :signup_source, :string, null: false, default: "admin_created"
      add :starts_on, :date
      add :expires_on, :date
      add :notes, :text
      add :referred_by_user_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :params, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:memberships, [:user_id])
    create index(:memberships, [:status])
    create index(:memberships, [:user_type_snapshot])
    create index(:memberships, [:expires_on])
    create index(:memberships, [:signup_source])
    create index(:memberships, [:referred_by_user_id])

    create constraint(:memberships, :memberships_user_type_snapshot_check,
             check: "user_type_snapshot IN ('member', 'athlete')"
           )

    create constraint(:memberships, :memberships_status_check,
             check:
               "status IN ('active', 'expiring', 'expired', 'cancelled', 'paused', 'trial', 'comped')"
           )

    create constraint(:memberships, :memberships_signup_source_check,
             check:
               "signup_source IN ('direct', 'referral', 'promo', 'admin_created', 'migrated', 'imported')"
           )

    create table(:membership_package_subscriptions, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :membership_id, references(:memberships, type: :binary_id, on_delete: :delete_all),
        null: false

      add :membership_package_id,
          references(:membership_packages, type: :binary_id, on_delete: :restrict),
          null: false

      add :status, :string, null: false, default: "active"
      add :starts_on, :date
      add :ends_on, :date
      add :package_code_snapshot, :string, null: false
      add :package_family_snapshot, :string, null: false
      add :billing_period_snapshot, :string, null: false
      add :price_cents_snapshot, :integer, null: false, default: 0
      add :params_snapshot, :map, null: false, default: %{}
      add :referral_reward_applied, :boolean, null: false, default: false

      timestamps(type: :utc_datetime_usec)
    end

    create index(:membership_package_subscriptions, [:membership_id])
    create index(:membership_package_subscriptions, [:membership_package_id])
    create index(:membership_package_subscriptions, [:status])
    create index(:membership_package_subscriptions, [:package_code_snapshot])
    create index(:membership_package_subscriptions, [:ends_on])

    create constraint(
             :membership_package_subscriptions,
             :membership_package_subscriptions_status_check,
             check: "status IN ('active', 'paused', 'cancelled', 'expired')"
           )

    create constraint(
             :membership_package_subscriptions,
             :membership_package_subscriptions_price_check,
             check: "price_cents_snapshot >= 0"
           )

    create table(:membership_payments, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :membership_id, references(:memberships, type: :binary_id, on_delete: :delete_all),
        null: false

      add :membership_package_subscription_id,
          references(:membership_package_subscriptions, type: :binary_id, on_delete: :nilify_all)

      add :amount_cents, :integer, null: false, default: 0
      add :currency, :string, null: false, default: "EUR"
      add :paid_on, :date
      add :payment_method, :string, null: false, default: "cash"
      add :payment_status, :string, null: false, default: "paid"
      add :notes, :text
      add :params, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create index(:membership_payments, [:membership_id])
    create index(:membership_payments, [:membership_package_subscription_id])
    create index(:membership_payments, [:paid_on])
    create index(:membership_payments, [:payment_method])
    create index(:membership_payments, [:payment_status])

    create constraint(:membership_payments, :membership_payments_amount_check,
             check: "amount_cents >= 0"
           )

    create constraint(:membership_payments, :membership_payments_method_check,
             check: "payment_method IN ('cash', 'bank_transfer', 'card_manual', 'other')"
           )

    create constraint(:membership_payments, :membership_payments_status_check,
             check: "payment_status IN ('paid', 'pending', 'refunded', 'failed', 'waived')"
           )

    create table(:promotion_campaigns, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :description, :text
      add :starts_on, :date
      add :ends_on, :date
      add :active, :boolean, null: false, default: true
      add :params, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create index(:promotion_campaigns, [:active])
    create index(:promotion_campaigns, [:starts_on, :ends_on])

    create table(:promotion_codes, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :promotion_campaign_id,
          references(:promotion_campaigns, type: :binary_id, on_delete: :delete_all),
          null: false

      add :code, :string, null: false
      add :discount_type, :string, null: false
      add :discount_value, :integer, null: false, default: 0
      add :max_redemptions, :integer
      add :active, :boolean, null: false, default: true
      add :params, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:promotion_codes, [:code])
    create index(:promotion_codes, [:promotion_campaign_id])
    create index(:promotion_codes, [:active])

    create constraint(:promotion_codes, :promotion_codes_discount_type_check,
             check: "discount_type IN ('percent', 'fixed_amount', 'free_period', 'manual')"
           )

    create constraint(:promotion_codes, :promotion_codes_discount_value_check,
             check: "discount_value >= 0"
           )

    create table(:promotion_redemptions, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :promotion_campaign_id,
          references(:promotion_campaigns, type: :binary_id, on_delete: :restrict),
          null: false

      add :promotion_code_id, references(:promotion_codes, type: :binary_id, on_delete: :restrict)

      add :membership_id, references(:memberships, type: :binary_id, on_delete: :delete_all),
        null: false

      add :membership_payment_id,
          references(:membership_payments, type: :binary_id, on_delete: :nilify_all)

      add :membership_package_subscription_id,
          references(:membership_package_subscriptions, type: :binary_id, on_delete: :nilify_all)

      add :discount_type_snapshot, :string, null: false
      add :discount_value_snapshot, :integer, null: false, default: 0
      add :redeemed_at, :utc_datetime_usec, null: false
      add :params, :map, null: false, default: %{}
    end

    create index(:promotion_redemptions, [:promotion_campaign_id])
    create index(:promotion_redemptions, [:promotion_code_id])
    create index(:promotion_redemptions, [:membership_id])
    create index(:promotion_redemptions, [:redeemed_at])

    create table(:referral_programs, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :description, :text
      add :active, :boolean, null: false, default: true
      add :reward_type, :string, null: false, default: "manual"
      add :reward_value, :integer, null: false, default: 0
      add :params, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create index(:referral_programs, [:active])

    create constraint(:referral_programs, :referral_programs_reward_type_check,
             check: "reward_type IN ('credit', 'discount', 'free_period', 'manual')"
           )

    create table(:referral_events, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :referral_program_id,
          references(:referral_programs, type: :binary_id, on_delete: :restrict)

      add :referrer_user_id, references(:users, type: :binary_id, on_delete: :nilify_all),
        null: false

      add :referred_user_id, references(:users, type: :binary_id, on_delete: :nilify_all),
        null: false

      add :membership_id, references(:memberships, type: :binary_id, on_delete: :nilify_all)
      add :status, :string, null: false, default: "pending"
      add :signup_source_snapshot, :string, null: false, default: "referral"
      add :notes, :text
      add :params, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create index(:referral_events, [:referral_program_id])
    create index(:referral_events, [:referrer_user_id])
    create index(:referral_events, [:referred_user_id])
    create index(:referral_events, [:status])

    create constraint(:referral_events, :referral_events_status_check,
             check: "status IN ('pending', 'approved', 'applied', 'rejected')"
           )

    create table(:referral_rewards, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :referral_event_id,
          references(:referral_events, type: :binary_id, on_delete: :delete_all),
          null: false

      add :recipient_user_id, references(:users, type: :binary_id, on_delete: :nilify_all),
        null: false

      add :membership_id, references(:memberships, type: :binary_id, on_delete: :nilify_all)
      add :reward_type, :string, null: false
      add :reward_value, :integer, null: false, default: 0
      add :status, :string, null: false, default: "pending"
      add :applied_at, :utc_datetime_usec
      add :params, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create index(:referral_rewards, [:referral_event_id])
    create index(:referral_rewards, [:recipient_user_id])
    create index(:referral_rewards, [:status])

    create constraint(:referral_rewards, :referral_rewards_status_check,
             check: "status IN ('pending', 'approved', 'applied', 'rejected')"
           )

    create table(:injury_reports, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      add :reported_by_id, references(:users, type: :binary_id, on_delete: :nilify_all),
        null: false

      add :reported_by_role, :string, null: false
      add :body_area, :string, null: false
      add :severity, :string, null: false, default: "mild"
      add :status, :string, null: false, default: "active"
      add :started_on, :date
      add :healed_on, :date
      add :description, :text
      add :training_limitations, :text
      add :tags, {:array, :string}, null: false, default: []
      add :visibility, :string, null: false, default: "user_and_admin"
      add :params, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create index(:injury_reports, [:user_id, :status])
    create index(:injury_reports, [:reported_by_id])
    create index(:injury_reports, [:body_area])
    create index(:injury_reports, [:severity])
    create index(:injury_reports, [:healed_on])

    create constraint(:injury_reports, :injury_reports_reported_by_role_check,
             check: "reported_by_role IN ('self', 'admin')"
           )

    create constraint(:injury_reports, :injury_reports_severity_check,
             check: "severity IN ('mild', 'moderate', 'severe')"
           )

    create constraint(:injury_reports, :injury_reports_status_check,
             check: "status IN ('active', 'healed')"
           )

    create constraint(:injury_reports, :injury_reports_visibility_check,
             check: "visibility IN ('admin_only', 'user_and_admin')"
           )

    create table(:injury_status_events, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :injury_report_id,
          references(:injury_reports, type: :binary_id, on_delete: :delete_all),
          null: false

      add :actor_id, references(:users, type: :binary_id, on_delete: :nilify_all), null: false
      add :event_type, :string, null: false
      add :payload, :map, null: false, default: %{}
      add :occurred_at, :utc_datetime_usec, null: false
    end

    create index(:injury_status_events, [:injury_report_id, :occurred_at])
    create index(:injury_status_events, [:actor_id])

    create constraint(:injury_status_events, :injury_status_events_type_check,
             check:
               "event_type IN ('reported', 'updated', 'marked_healed', 'reopened', 'note_added')"
           )

    create table(:review_questionnaires, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :target_type, :string, null: false
      add :version, :integer, null: false, default: 1
      add :questions, {:array, :map}, null: false, default: []
      add :active, :boolean, null: false, default: true

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:review_questionnaires, [:target_type, :version])
    create index(:review_questionnaires, [:target_type, :active])

    create table(:reviews, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :target_type, :string, null: false
      add :target_id, :binary_id
      add :target_snapshot, :map, null: false, default: %{}

      add :questionnaire_id,
          references(:review_questionnaires, type: :binary_id, on_delete: :nilify_all)

      add :rating, :integer
      add :sentiment, :string, null: false, default: "neutral"
      add :visibility, :string, null: false, default: "user_visible"
      add :body, :text
      add :status, :string, null: false, default: "open"
      add :tags, {:array, :string}, null: false, default: []
      add :params, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create index(:reviews, [:user_id, :inserted_at])
    create index(:reviews, [:target_type, :target_id])
    create index(:reviews, [:rating])
    create index(:reviews, [:sentiment])
    create index(:reviews, [:status])

    create constraint(:reviews, :reviews_rating_check,
             check: "rating IS NULL OR (rating >= 1 AND rating <= 5)"
           )

    create constraint(:reviews, :reviews_sentiment_check,
             check: "sentiment IN ('positive', 'neutral', 'negative', 'mixed')"
           )

    create constraint(:reviews, :reviews_visibility_check,
             check: "visibility IN ('admin_only', 'user_visible')"
           )

    create constraint(:reviews, :reviews_status_check,
             check: "status IN ('open', 'reviewed', 'archived', 'needs_follow_up')"
           )

    create table(:review_answers, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :review_id, references(:reviews, type: :binary_id, on_delete: :delete_all), null: false
      add :question_key, :string, null: false
      add :question_text, :text, null: false
      add :answer_text, :text
      add :rating_value, :integer

      timestamps(type: :utc_datetime_usec)
    end

    create index(:review_answers, [:review_id])
    create index(:review_answers, [:question_key])

    create constraint(:review_answers, :review_answers_rating_value_check,
             check: "rating_value IS NULL OR (rating_value >= 1 AND rating_value <= 5)"
           )

    create table(:attendance_records, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :scheduled_class_id,
          references(:scheduled_classes, type: :binary_id, on_delete: :delete_all),
          null: false

      add :booking_id, references(:bookings, type: :binary_id, on_delete: :nilify_all)
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :status, :string, null: false, default: "attended"
      add :marked_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :marked_at, :utc_datetime_usec, null: false
      add :notes, :text
      add :params, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:attendance_records, [:scheduled_class_id, :user_id])
    create index(:attendance_records, [:user_id, :marked_at])
    create index(:attendance_records, [:status])

    create constraint(:attendance_records, :attendance_records_status_check,
             check: "status IN ('attended', 'missed', 'cancelled', 'late_cancel', 'no_show')"
           )

    create table(:exercise_catalog_entries, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :normalized_name, :string, null: false
      add :movement_pattern, :string
      add :equipment, {:array, :string}, null: false, default: []
      add :muscle_groups, {:array, :string}, null: false, default: []
      add :skill_domain, :string
      add :progression_level, :string
      add :tags, {:array, :string}, null: false, default: []
      add :params, :map, null: false, default: %{}
      add :active, :boolean, null: false, default: true

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:exercise_catalog_entries, [:normalized_name])
    create index(:exercise_catalog_entries, [:movement_pattern])
    create index(:exercise_catalog_entries, [:skill_domain])
    create index(:exercise_catalog_entries, [:active])

    create table(:communication_threads, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :context_type, :string, null: false
      add :context_id, :binary_id
      add :status, :string, null: false, default: "open"

      add :created_by_id, references(:users, type: :binary_id, on_delete: :nilify_all),
        null: false

      add :assigned_admin_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :last_message_at, :utc_datetime_usec
      add :needs_follow_up_at, :utc_datetime_usec
      add :params, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create index(:communication_threads, [:context_type, :context_id])
    create index(:communication_threads, [:status])
    create index(:communication_threads, [:assigned_admin_id])

    create constraint(:communication_threads, :communication_threads_status_check,
             check: "status IN ('open', 'resolved', 'needs_follow_up')"
           )

    create table(:communication_messages, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :thread_id,
          references(:communication_threads, type: :binary_id, on_delete: :delete_all),
          null: false

      add :sender_id, references(:users, type: :binary_id, on_delete: :nilify_all), null: false
      add :recipient_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :sender_role_snapshot, :string, null: false
      add :recipient_role_snapshot, :string
      add :direction, :string, null: false
      add :channel, :string, null: false, default: "in_app"
      add :body, :text, null: false
      add :sentiment_tag, :string
      add :sent_at, :utc_datetime_usec, null: false
      add :params, :map, null: false, default: %{}

      timestamps(updated_at: false, type: :utc_datetime_usec)
    end

    create index(:communication_messages, [:thread_id, :sent_at])
    create index(:communication_messages, [:sender_id])
    create index(:communication_messages, [:recipient_id])
    create index(:communication_messages, [:direction])
    create index(:communication_messages, [:channel])

    create constraint(:communication_messages, :communication_messages_direction_check,
             check: "direction IN ('user_to_admin', 'admin_to_user', 'admin_to_admin')"
           )

    create constraint(:communication_messages, :communication_messages_channel_check,
             check: "channel IN ('in_app', 'push', 'email', 'sms', 'manual')"
           )

    create table(:analytics_events, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :event_name, :string, null: false
      add :user_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :actor_role_snapshot, :string
      add :context_type, :string
      add :context_id, :binary_id
      add :occurred_at, :utc_datetime_usec, null: false
      add :metadata, :map, null: false, default: %{}
    end

    create index(:analytics_events, [:event_name, :occurred_at])
    create index(:analytics_events, [:user_id, :occurred_at])
    create index(:analytics_events, [:context_type, :context_id])

    create table(:notification_click_events, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :notification_id, references(:notifications, type: :binary_id, on_delete: :delete_all),
        null: false

      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :url, :text
      add :clicked_at, :utc_datetime_usec, null: false
      add :metadata, :map, null: false, default: %{}
    end

    create index(:notification_click_events, [:notification_id])
    create index(:notification_click_events, [:user_id, :clicked_at])

    create table(:push_dispatch_attempts, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :notification_id, references(:notifications, type: :binary_id, on_delete: :nilify_all)
      add :user_id, references(:users, type: :binary_id, on_delete: :nilify_all), null: false
      add :endpoint_hash, :string, null: false
      add :status, :string, null: false, default: "pending"
      add :attempted_at, :utc_datetime_usec, null: false
      add :completed_at, :utc_datetime_usec
      add :error, :text
      add :metadata, :map, null: false, default: %{}
    end

    create index(:push_dispatch_attempts, [:notification_id])
    create index(:push_dispatch_attempts, [:user_id, :attempted_at])
    create index(:push_dispatch_attempts, [:status])

    create constraint(:push_dispatch_attempts, :push_dispatch_attempts_status_check,
             check: "status IN ('pending', 'sent', 'failed', 'expired')"
           )

    execute("""
    CREATE MATERIALIZED VIEW finance_aggregates AS
    SELECT
      date_trunc('month', COALESCE(mp.paid_on::timestamp, m.inserted_at))::date AS period_start,
      COALESCE(m.user_type_snapshot, 'unknown') AS user_type_snapshot,
      COALESCE(mps.package_code_snapshot, 'unassigned') AS package_code,
      COALESCE(mps.package_family_snapshot, 'unassigned') AS package_family,
      COUNT(DISTINCT m.id)::integer AS membership_count,
      COUNT(DISTINCT m.id) FILTER (WHERE m.status = 'active')::integer AS active_membership_count,
      COUNT(DISTINCT m.id) FILTER (
        WHERE m.expires_on IS NOT NULL
          AND m.expires_on <= (timezone('utc', now())::date + interval '30 days')
          AND m.status IN ('active', 'expiring', 'trial')
      )::integer AS expiring_membership_count,
      COALESCE(SUM(mp.amount_cents) FILTER (WHERE mp.payment_status = 'paid'), 0)::bigint AS paid_revenue_cents,
      COALESCE(SUM(mp.amount_cents) FILTER (WHERE mp.payment_status = 'pending'), 0)::bigint AS pending_revenue_cents,
      COUNT(DISTINCT pr.id)::integer AS promotion_redemption_count,
      COALESCE(SUM(pr.discount_value_snapshot), 0)::bigint AS promotion_discount_value,
      COUNT(DISTINCT re.id)::integer AS referral_signup_count,
      COUNT(DISTINCT rr.id) FILTER (WHERE rr.status = 'pending')::integer AS pending_referral_reward_count
    FROM memberships m
    LEFT JOIN membership_package_subscriptions mps ON mps.membership_id = m.id
    LEFT JOIN membership_payments mp ON mp.membership_id = m.id
    LEFT JOIN promotion_redemptions pr ON pr.membership_id = m.id
    LEFT JOIN referral_events re ON re.membership_id = m.id
    LEFT JOIN referral_rewards rr ON rr.membership_id = m.id
    GROUP BY period_start, user_type_snapshot, package_code, package_family
    WITH NO DATA
    """)

    execute("""
    CREATE UNIQUE INDEX finance_aggregates_period_user_type_package_index
    ON finance_aggregates (period_start, user_type_snapshot, package_code, package_family)
    """)

    execute("""
    CREATE MATERIALIZED VIEW coaching_aggregates AS
    SELECT
      date_trunc('week', timezone('utc', now()))::date AS period_start,
      COUNT(DISTINCT u.id) FILTER (WHERE u.role = 'athlete')::integer AS active_athlete_count,
      COUNT(DISTINCT u.id) FILTER (
        WHERE u.role = 'athlete'
          AND NOT EXISTS (
            SELECT 1
            FROM workout_executions we_recent
            WHERE we_recent.user_id = u.id
              AND we_recent.completed_at_utc >= timezone('utc', now()) - interval '14 days'
          )
      )::integer AS inactive_athlete_count,
      COUNT(DISTINCT we.id) FILTER (
        WHERE we.completed_at_utc >= date_trunc('week', timezone('utc', now()))
      )::integer AS completed_workouts_this_week,
      COUNT(DISTINCT n.id) FILTER (
        WHERE n.inserted_at >= date_trunc('week', timezone('utc', now()))
      )::integer AS coach_notes_this_week,
      COALESCE(
        (
          COUNT(DISTINCT we.id) FILTER (
            WHERE we.completed_at_utc >= date_trunc('week', timezone('utc', now()))
          )::float
          / NULLIF(COUNT(DISTINCT u.id) FILTER (WHERE u.role = 'athlete'), 0)
        ),
        0.0
      ) AS average_completion_rate,
      COUNT(DISTINCT we.id) FILTER (
        WHERE cardinality(we.exercise_notes) > 0
          AND we.completed_at_utc >= timezone('utc', now()) - interval '30 days'
      )::integer AS recent_workout_note_count
    FROM users u
    LEFT JOIN workout_executions we ON we.user_id = u.id
    LEFT JOIN admin_athlete_notes n ON n.athlete_id = u.id
    WITH NO DATA
    """)

    execute(
      "CREATE UNIQUE INDEX coaching_aggregates_period_start_index ON coaching_aggregates (period_start)"
    )

    execute("REFRESH MATERIALIZED VIEW finance_aggregates")
    execute("REFRESH MATERIALIZED VIEW coaching_aggregates")
  end

  def down do
    execute("DROP MATERIALIZED VIEW IF EXISTS coaching_aggregates")
    execute("DROP MATERIALIZED VIEW IF EXISTS finance_aggregates")

    drop table(:push_dispatch_attempts)
    drop table(:notification_click_events)
    drop table(:analytics_events)
    drop table(:communication_messages)
    drop table(:communication_threads)
    drop table(:exercise_catalog_entries)
    drop table(:attendance_records)
    drop table(:review_answers)
    drop table(:reviews)
    drop table(:review_questionnaires)
    drop table(:injury_status_events)
    drop table(:injury_reports)
    drop table(:referral_rewards)
    drop table(:referral_events)
    drop table(:referral_programs)
    drop table(:promotion_redemptions)
    drop table(:promotion_codes)
    drop table(:promotion_campaigns)
    drop table(:membership_payments)
    drop table(:membership_package_subscriptions)
    drop table(:memberships)
    drop table(:membership_packages)
  end
end
