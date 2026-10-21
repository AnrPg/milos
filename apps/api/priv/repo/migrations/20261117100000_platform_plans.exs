defmodule Palee.Repo.Migrations.PlatformPlans do
  @moduledoc """
  ADR-170 (P3-M8): the solo-coach tier and the platform plans behind it.

  - `platform_plans`: the platform's SaaS catalog (vision §5.3), one row per
    plan: audience (`gym` | `coach`), limits (`staff_seats`,
    `active_clients`; absent = unlimited), monthly and annual prices,
    `price_status` (`placeholder` until the owner of the platform confirms
    the price, brief §10 Q2), trial length, and whether it is the default
    plan of its audience. Global, not tenant data: everyone may read it (a
    pricing page), only vendors or system sessions write it.
  - `organization_platform_subscriptions`: the plan an organization is on,
    with status (`trialing`, `active`, `past_due`, `cancelled`, `comped`),
    trial end and a negotiated price. Platform-administered: the owners and
    admins of the organization read it, only vendors and system sessions
    write it.
  - `palee_ensure_platform_subscription(org)`: the one write an organization's
    own admin may cause. It starts the default plan of the organization's
    kind, on trial when the plan has one, and never changes an existing row,
    so a creator can never pick or extend their own plan.
  - `palee_organization_slug_taken(slug)`: whether a slug is used by any
    organization or retired alias. A self-serve coach cannot see other
    organizations, yet their practice needs a free slug; slugs are public
    (`/b/<slug>`), so the answer reveals nothing new.
  - `appointment_slots.mode` (`in_person` | `online`) and `meeting_url`: an
    independent coach trains in a park, a gym or online (vision §7.10).
  """

  use Ecto.Migration

  @acting_user "NULLIF(current_setting('app.user_id', true), '')::uuid"
  @acting_org "NULLIF(current_setting('app.organization_id', true), '')::uuid"

  def up do
    create table(:platform_plans, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :code, :text, null: false
      add :audience, :text, null: false
      add :name, :text, null: false
      add :description, :text
      add :limits, :jsonb, null: false, default: fragment("'{}'::jsonb")
      add :monthly_price_cents, :integer
      add :annual_price_cents, :integer
      add :currency, :text, null: false, default: "EUR"
      add :price_status, :text, null: false, default: "placeholder"
      add :trial_days, :integer, null: false, default: 0
      add :is_default, :boolean, null: false, default: false
      add :public, :boolean, null: false, default: true
      add :active, :boolean, null: false, default: true
      add :position, :integer, null: false, default: 0

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:platform_plans, [:code])

    create unique_index(:platform_plans, [:audience],
             where: "is_default",
             name: :platform_plans_one_default_per_audience_index
           )

    create constraint(:platform_plans, :platform_plans_code_check,
             check: "code ~ '^[a-z][a-z0-9_]{1,39}$'"
           )

    create constraint(:platform_plans, :platform_plans_audience_check,
             check: "audience IN ('gym', 'coach')"
           )

    create constraint(:platform_plans, :platform_plans_name_check,
             check: "char_length(name) BETWEEN 1 AND 80"
           )

    create constraint(:platform_plans, :platform_plans_description_check,
             check: "description IS NULL OR char_length(description) <= 500"
           )

    create constraint(:platform_plans, :platform_plans_limits_check,
             check: "jsonb_typeof(limits) = 'object'"
           )

    create constraint(:platform_plans, :platform_plans_prices_check,
             check:
               "(monthly_price_cents IS NULL OR monthly_price_cents >= 0) AND " <>
                 "(annual_price_cents IS NULL OR annual_price_cents >= 0)"
           )

    create constraint(:platform_plans, :platform_plans_currency_check,
             check: "currency ~ '^[A-Z]{3}$'"
           )

    create constraint(:platform_plans, :platform_plans_price_status_check,
             check: "price_status IN ('placeholder', 'confirmed')"
           )

    create constraint(:platform_plans, :platform_plans_trial_days_check,
             check: "trial_days BETWEEN 0 AND 365"
           )

    create constraint(:platform_plans, :platform_plans_default_active_check,
             check: "NOT is_default OR active"
           )

    # Placeholder prices (brief §10 Q2 is open): the platform console shows
    # them as «placeholder» until a vendor confirms each one.
    execute("""
    INSERT INTO platform_plans
      (id, code, audience, name, description, limits, monthly_price_cents,
       annual_price_cents, currency, price_status, trial_days, is_default,
       public, active, position, inserted_at, updated_at)
    VALUES
      (gen_random_uuid(), 'solo_coach', 'coach', 'Solo coach',
       'For an independent coach: clients, programmes, sessions, packages, a team club and open bootcamps.',
       '{"staff_seats": 2, "active_clients": 50}'::jsonb, 1900, 19000, 'EUR',
       'placeholder', 30, true, true, true, 10, now(), now()),
      (gen_random_uuid(), 'gym', 'gym', 'Gym',
       'Everything Palee offers a gym, without limits.',
       '{}'::jsonb, NULL, NULL, 'EUR', 'placeholder', 0, true, true, true, 20, now(), now())
    """)

    execute("""
    CREATE POLICY platform_plans_read_policy ON platform_plans
      FOR SELECT
      USING (true)
    """)

    execute("""
    CREATE POLICY platform_plans_write_policy ON platform_plans
      FOR ALL
      USING (#{@acting_user} IS NULL OR palee_acting_user_is_vendor())
      WITH CHECK (#{@acting_user} IS NULL OR palee_acting_user_is_vendor())
    """)

    execute("ALTER TABLE platform_plans ENABLE ROW LEVEL SECURITY")
    execute("ALTER TABLE platform_plans FORCE ROW LEVEL SECURITY")

    create table(:organization_platform_subscriptions, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id,
          references(:organizations, type: :binary_id, on_delete: :delete_all),
          null: false

      add :plan_code,
          references(:platform_plans,
            column: :code,
            type: :text,
            on_delete: :restrict,
            on_update: :update_all
          ),
          null: false

      add :status, :text, null: false
      add :trial_ends_at, :utc_datetime_usec
      add :price_override_cents, :integer
      add :notes, :text
      add :updated_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:organization_platform_subscriptions, [:organization_id])
    create index(:organization_platform_subscriptions, [:plan_code])

    create constraint(
             :organization_platform_subscriptions,
             :organization_platform_subscriptions_status_check,
             check: "status IN ('trialing', 'active', 'past_due', 'cancelled', 'comped')"
           )

    create constraint(
             :organization_platform_subscriptions,
             :organization_platform_subscriptions_trial_check,
             check: "status <> 'trialing' OR trial_ends_at IS NOT NULL"
           )

    create constraint(
             :organization_platform_subscriptions,
             :organization_platform_subscriptions_override_check,
             check: "price_override_cents IS NULL OR price_override_cents >= 0"
           )

    create constraint(
             :organization_platform_subscriptions,
             :organization_platform_subscriptions_notes_check,
             check: "notes IS NULL OR char_length(notes) <= 1000"
           )

    # Owners and admins read their organization's plan; vendors read all; a
    # session scoped to the organization without a user (a cron job) reads
    # its own. Only vendors and system sessions write.
    execute("""
    CREATE POLICY organization_platform_subscriptions_read_policy
      ON organization_platform_subscriptions
      FOR SELECT
      USING (
        palee_acting_user_is_vendor()
        OR palee_acting_user_administers(organization_id)
        OR (#{@acting_user} IS NULL AND organization_id = #{@acting_org})
      )
    """)

    execute("""
    CREATE POLICY organization_platform_subscriptions_write_policy
      ON organization_platform_subscriptions
      FOR ALL
      USING (#{@acting_user} IS NULL OR palee_acting_user_is_vendor())
      WITH CHECK (#{@acting_user} IS NULL OR palee_acting_user_is_vendor())
    """)

    execute("ALTER TABLE organization_platform_subscriptions ENABLE ROW LEVEL SECURITY")
    execute("ALTER TABLE organization_platform_subscriptions FORCE ROW LEVEL SECURITY")

    # The default plan of the organization's kind, started once. Callable by
    # a vendor, a system session or an admin of that organization (the owner
    # who just created it); it never touches an existing subscription.
    execute("""
    CREATE OR REPLACE FUNCTION palee_ensure_platform_subscription(org_id uuid)
    RETURNS void
    LANGUAGE plpgsql
    VOLATILE
    SECURITY DEFINER
    SET search_path = public, pg_temp
    AS $$
    BEGIN
      IF NOT (
        #{@acting_user} IS NULL
        OR palee_acting_user_is_vendor()
        OR palee_acting_user_administers(org_id)
      ) THEN
        RAISE EXCEPTION 'not allowed to start a platform subscription'
          USING ERRCODE = 'insufficient_privilege';
      END IF;

      INSERT INTO organization_platform_subscriptions
        (id, organization_id, plan_code, status, trial_ends_at, inserted_at, updated_at)
      SELECT gen_random_uuid(), o.id, p.code,
             CASE WHEN p.trial_days > 0 THEN 'trialing' ELSE 'active' END,
             CASE WHEN p.trial_days > 0 THEN now() + make_interval(days => p.trial_days) END,
             now(), now()
      FROM organizations o
      JOIN platform_plans p ON p.audience = o.provider_kind AND p.is_default
      WHERE o.id = org_id
      ON CONFLICT (organization_id) DO NOTHING;
    END
    $$
    """)

    # Organizations that exist today keep working as they do: their kind's
    # default plan, active (never put on a trial retroactively).
    execute("""
    INSERT INTO organization_platform_subscriptions
      (id, organization_id, plan_code, status, inserted_at, updated_at)
    SELECT gen_random_uuid(), o.id, p.code, 'active', now(), now()
    FROM organizations o
    JOIN platform_plans p ON p.audience = o.provider_kind AND p.is_default
    ON CONFLICT (organization_id) DO NOTHING
    """)

    execute("""
    CREATE OR REPLACE FUNCTION palee_organization_slug_taken(candidate text)
    RETURNS boolean
    LANGUAGE sql
    STABLE
    SECURITY DEFINER
    SET search_path = public, pg_temp
    AS $$
      SELECT EXISTS (SELECT 1 FROM organizations WHERE slug = candidate)
          OR EXISTS (SELECT 1 FROM organization_slug_aliases WHERE slug = candidate)
    $$
    """)

    alter table(:appointment_slots) do
      add :mode, :text, null: false, default: "in_person"
      add :meeting_url, :text
    end

    create constraint(:appointment_slots, :appointment_slots_mode_check,
             check: "mode IN ('in_person', 'online')"
           )

    create constraint(:appointment_slots, :appointment_slots_meeting_url_check,
             check:
               "meeting_url IS NULL OR (mode = 'online' AND meeting_url ~ '^https://' " <>
                 "AND char_length(meeting_url) <= 500)"
           )
  end

  def down do
    drop constraint(:appointment_slots, :appointment_slots_meeting_url_check)
    drop constraint(:appointment_slots, :appointment_slots_mode_check)

    alter table(:appointment_slots) do
      remove :meeting_url
      remove :mode
    end

    execute("DROP FUNCTION IF EXISTS palee_organization_slug_taken(text)")
    execute("DROP FUNCTION IF EXISTS palee_ensure_platform_subscription(uuid)")
    drop table(:organization_platform_subscriptions)
    drop table(:platform_plans)
  end
end
