defmodule Palee.Repo.Migrations.BusinessActivation do
  @moduledoc """
  ADR-184: business accounts start in demo mode until the platform team
  activates them.

  - `organizations.activation` (`demo` | `active`, default `active`, so every
    existing organization is backfilled as active), `demo_started_at`,
    `activated_at` and `activated_by_id` (the vendor who issued the link that
    activated it). Only gym and coach organizations can be in demo mode
    (organisers, ADR-185, are plain people hosting events and never are).
    A trigger refuses any change of `activation` that does not come from a
    vendor, a system session or `palee_activate_business/2`.
  - `business_activation_links`: a vendor's one-time link for one account
    and one role (owner | admin), platform-administered. The account it is
    for reads it; only vendors and system sessions write it.
  - `business_requests`: a person's request to the platform team, either to
    convert a plain account into a business (`conversion`) or to activate a
    demo business (`activation`). The requester reads and files their own and
    may cancel a pending one; vendors decide.
  - `demo_records`: every row the demo seeders wrote, by section, so that
    activation (or «remove demo data») deletes exactly those rows. Tenant
    data under RLS.
  - `palee_activate_business(digest, now)`: the only path from demo to
    active for a non-vendor: the signed-in account redeems its own link.
  - `palee_notification_suppressed(org, user)`: a demo person never gets a
    notification, and a demo business notifies nobody outside its own staff.
  - The discovery and public lookups (ADR-142, ADR-154, ADR-156) only answer
    for active organizations.
  """

  use Ecto.Migration

  @acting_user "NULLIF(current_setting('app.user_id', true), '')::uuid"
  @acting_org "NULLIF(current_setting('app.organization_id', true), '')::uuid"
  @live "AND o.activation = 'active'"

  def up do
    alter table(:organizations) do
      add :activation, :text, null: false, default: "active"
      add :demo_started_at, :utc_datetime_usec
      add :activated_at, :utc_datetime_usec
      add :activated_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
    end

    create constraint(:organizations, :organizations_activation_check,
             check: "activation IN ('demo', 'active')"
           )

    create constraint(:organizations, :organizations_activation_kind_check,
             check: "activation = 'active' OR provider_kind IN ('gym', 'coach')"
           )

    create index(:organizations, [:activation], where: "activation = 'demo'")

    execute("""
    CREATE OR REPLACE FUNCTION palee_guard_organization_activation()
    RETURNS trigger
    LANGUAGE plpgsql
    AS $$
    BEGIN
      IF NEW.activation IS DISTINCT FROM OLD.activation
         AND #{@acting_user} IS NOT NULL
         AND NOT palee_acting_user_is_vendor()
         AND COALESCE(current_setting('palee.activation_write', true), '') <> 'on' THEN
        RAISE EXCEPTION 'business activation is decided by the platform team'
          USING ERRCODE = 'insufficient_privilege';
      END IF;

      RETURN NEW;
    END
    $$
    """)

    execute("""
    CREATE TRIGGER organizations_activation_guard
      BEFORE UPDATE OF activation ON organizations
      FOR EACH ROW EXECUTE FUNCTION palee_guard_organization_activation()
    """)

    create_activation_links()
    create_business_requests()
    create_demo_records()
    create_functions()
    redefine_public_lookups(@live)
  end

  def down do
    redefine_public_lookups("")

    execute("DROP FUNCTION IF EXISTS palee_notification_suppressed(uuid, uuid)")
    execute("DROP FUNCTION IF EXISTS palee_activate_business(bytea, timestamptz)")
    drop table(:demo_records)
    drop table(:business_requests)
    drop table(:business_activation_links)
    execute("DROP TRIGGER IF EXISTS organizations_activation_guard ON organizations")
    execute("DROP FUNCTION IF EXISTS palee_guard_organization_activation()")
    drop index(:organizations, [:activation])
    drop constraint(:organizations, :organizations_activation_kind_check)
    drop constraint(:organizations, :organizations_activation_check)

    alter table(:organizations) do
      remove :activated_by_id
      remove :activated_at
      remove :demo_started_at
      remove :activation
    end
  end

  defp create_activation_links do
    create table(:business_activation_links, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id,
          references(:organizations, type: :binary_id, on_delete: :delete_all),
          null: false

      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :role, :text, null: false
      add :token_digest, :binary, null: false
      add :expires_at, :utc_datetime_usec, null: false
      add :created_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :redeemed_at, :utc_datetime_usec
      add :revoked_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:business_activation_links, [:token_digest])
    create index(:business_activation_links, [:user_id])

    # One live link per organization; issuing a new one revokes the old one.
    create unique_index(:business_activation_links, [:organization_id],
             where: "redeemed_at IS NULL AND revoked_at IS NULL",
             name: :business_activation_links_one_live_index
           )

    create constraint(:business_activation_links, :business_activation_links_role_check,
             check: "role IN ('owner', 'admin')"
           )

    execute("""
    CREATE POLICY business_activation_links_read_policy ON business_activation_links
      FOR SELECT
      USING (
        #{@acting_user} IS NULL
        OR palee_acting_user_is_vendor()
        OR user_id = #{@acting_user}
      )
    """)

    execute("""
    CREATE POLICY business_activation_links_write_policy ON business_activation_links
      FOR ALL
      USING (#{@acting_user} IS NULL OR palee_acting_user_is_vendor())
      WITH CHECK (#{@acting_user} IS NULL OR palee_acting_user_is_vendor())
    """)

    execute("ALTER TABLE business_activation_links ENABLE ROW LEVEL SECURITY")
    execute("ALTER TABLE business_activation_links FORCE ROW LEVEL SECURITY")
  end

  defp create_business_requests do
    create table(:business_requests, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :kind, :text, null: false
      add :business_kind, :text, null: false
      add :business_name, :text, null: false
      add :city, :text
      add :phone, :text
      add :message, :text
      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all)
      add :status, :text, null: false, default: "pending"
      add :decided_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :decided_at, :utc_datetime_usec
      add :decision_note, :text

      timestamps(type: :utc_datetime_usec)
    end

    create index(:business_requests, [:status, :inserted_at])
    create index(:business_requests, [:organization_id])

    create unique_index(:business_requests, [:user_id, :kind],
             where: "status = 'pending'",
             name: :business_requests_one_pending_index
           )

    create constraint(:business_requests, :business_requests_kind_check,
             check: "kind IN ('conversion', 'activation')"
           )

    create constraint(:business_requests, :business_requests_business_kind_check,
             check: "business_kind IN ('gym', 'coach')"
           )

    create constraint(:business_requests, :business_requests_status_check,
             check: "status IN ('pending', 'approved', 'declined', 'cancelled', 'completed')"
           )

    create constraint(:business_requests, :business_requests_text_check,
             check:
               "char_length(business_name) BETWEEN 2 AND 120 " <>
                 "AND (city IS NULL OR char_length(city) <= 80) " <>
                 "AND (phone IS NULL OR char_length(phone) <= 40) " <>
                 "AND (message IS NULL OR char_length(message) <= 1000) " <>
                 "AND (decision_note IS NULL OR char_length(decision_note) <= 500)"
           )

    create constraint(:business_requests, :business_requests_activation_org_check,
             check: "kind <> 'activation' OR organization_id IS NOT NULL"
           )

    execute("""
    CREATE POLICY business_requests_read_policy ON business_requests
      FOR SELECT
      USING (
        #{@acting_user} IS NULL
        OR palee_acting_user_is_vendor()
        OR user_id = #{@acting_user}
      )
    """)

    # A person files their own request, always pending and never decided.
    execute("""
    CREATE POLICY business_requests_insert_policy ON business_requests
      FOR INSERT
      WITH CHECK (
        #{@acting_user} IS NULL
        OR palee_acting_user_is_vendor()
        OR (user_id = #{@acting_user} AND status = 'pending' AND decided_by_id IS NULL
            AND decided_at IS NULL)
      )
    """)

    # The requester may only withdraw a pending request; vendors decide.
    execute("""
    CREATE POLICY business_requests_update_policy ON business_requests
      FOR UPDATE
      USING (
        #{@acting_user} IS NULL
        OR palee_acting_user_is_vendor()
        OR (user_id = #{@acting_user} AND status = 'pending')
      )
      WITH CHECK (
        #{@acting_user} IS NULL
        OR palee_acting_user_is_vendor()
        OR (user_id = #{@acting_user} AND status IN ('pending', 'cancelled')
            AND decided_by_id IS NULL)
      )
    """)

    execute("""
    CREATE POLICY business_requests_delete_policy ON business_requests
      FOR DELETE
      USING (#{@acting_user} IS NULL OR palee_acting_user_is_vendor())
    """)

    execute("ALTER TABLE business_requests ENABLE ROW LEVEL SECURITY")
    execute("ALTER TABLE business_requests FORCE ROW LEVEL SECURITY")
  end

  defp create_demo_records do
    create table(:demo_records) do
      add :organization_id,
          references(:organizations, type: :binary_id, on_delete: :delete_all),
          null: false

      add :section, :text, null: false
      add :source, :text, null: false
      add :record_id, :binary_id, null: false

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(:demo_records, [:organization_id, :source, :record_id])
    create index(:demo_records, [:organization_id, :section])
    create index(:demo_records, [:record_id], where: "source = 'users'")

    create constraint(:demo_records, :demo_records_section_check,
             check: "section ~ '^[a-z][a-z_]{1,39}$'"
           )

    create constraint(:demo_records, :demo_records_source_check,
             check: "source ~ '^[a-z][a-z_]{1,62}$'"
           )

    execute("""
    CREATE POLICY demo_records_tenant_policy ON demo_records
      FOR ALL
      USING (organization_id = #{@acting_org})
      WITH CHECK (organization_id = #{@acting_org})
    """)

    execute("ALTER TABLE demo_records ENABLE ROW LEVEL SECURITY")
    execute("ALTER TABLE demo_records FORCE ROW LEVEL SECURITY")
  end

  defp create_functions do
    # The signed-in account redeems the link issued for it: the organization
    # becomes active, the link is spent, a pending activation request is
    # completed and, when the organization is still on its creation trial,
    # the trial restarts from the activation day (ADR-170: a demo period is
    # not paid time). The demo data is deleted by the caller in the same
    # transaction, before this runs.
    execute("""
    CREATE OR REPLACE FUNCTION palee_activate_business(p_digest bytea, p_now timestamptz)
    RETURNS uuid
    LANGUAGE plpgsql
    VOLATILE
    SECURITY DEFINER
    SET search_path = public, pg_temp
    AS $$
    DECLARE
      v_user uuid := #{@acting_user};
      v_link public.business_activation_links%ROWTYPE;
    BEGIN
      SELECT * INTO v_link
      FROM public.business_activation_links
      WHERE token_digest = p_digest
      FOR UPDATE;

      IF NOT FOUND OR v_user IS NULL OR v_link.user_id <> v_user
         OR v_link.redeemed_at IS NOT NULL OR v_link.revoked_at IS NOT NULL
         OR v_link.expires_at <= p_now THEN
        RAISE EXCEPTION 'invalid_activation_link' USING ERRCODE = 'P0001';
      END IF;

      PERFORM set_config('palee.activation_write', 'on', true);

      UPDATE public.organizations
      SET activation = 'active', activated_at = p_now, activated_by_id = v_link.created_by_id,
          updated_at = p_now
      WHERE id = v_link.organization_id AND activation = 'demo';

      IF NOT FOUND THEN
        PERFORM set_config('palee.activation_write', '', true);
        RAISE EXCEPTION 'business_already_active' USING ERRCODE = 'P0001';
      END IF;

      PERFORM set_config('palee.activation_write', '', true);

      UPDATE public.business_activation_links
      SET redeemed_at = p_now, updated_at = p_now
      WHERE id = v_link.id;

      UPDATE public.business_requests
      SET status = 'completed', decided_by_id = v_link.created_by_id, decided_at = p_now,
          updated_at = p_now
      WHERE organization_id = v_link.organization_id AND kind = 'activation'
        AND status = 'pending';

      UPDATE public.organization_platform_subscriptions s
      SET status = CASE WHEN p.trial_days > 0 THEN 'trialing' ELSE 'active' END,
          trial_ends_at = CASE WHEN p.trial_days > 0
                               THEN p_now + make_interval(days => p.trial_days) END,
          updated_at = p_now
      FROM public.platform_plans p
      WHERE s.organization_id = v_link.organization_id
        AND p.code = s.plan_code
        AND s.status = 'trialing';

      RETURN v_link.organization_id;
    END
    $$
    """)

    # One answer, no row data: whether a notification to this account (about
    # this organization, when there is one) must not be delivered.
    execute("""
    CREATE OR REPLACE FUNCTION palee_notification_suppressed(p_org uuid, p_user uuid)
    RETURNS boolean
    LANGUAGE sql
    STABLE
    SECURITY DEFINER
    SET search_path = public, pg_temp
    AS $$
      SELECT EXISTS (
               SELECT 1 FROM public.demo_records d
               WHERE d.source = 'users' AND d.record_id = p_user)
          OR EXISTS (
               SELECT 1 FROM public.organizations o
               WHERE o.id = p_org AND o.activation = 'demo'
                 AND NOT EXISTS (
                   SELECT 1 FROM public.organization_memberships m
                   WHERE m.organization_id = o.id AND m.user_id = p_user
                     AND m.status = 'active'
                     AND m.roles && ARRAY['owner', 'admin', 'coach', 'front_desk',
                                          'accountant', 'janitor']::varchar[]))
    $$
    """)
  end

  # The discovery and public lookups, with the activation predicate added
  # (`live`) or removed (down). Bodies are otherwise those of the migrations
  # that introduced them (20261020100000, 20261024100000, referrals).
  defp redefine_public_lookups(live) do
    execute("""
    CREATE OR REPLACE FUNCTION palee_public_box_by_slug(box_slug text)
     RETURNS TABLE(organization_id uuid, slug text)
     LANGUAGE sql
     STABLE SECURITY DEFINER
     SET search_path TO 'public', 'pg_temp'
    AS $function$
      SELECT o.id, o.slug::text
      FROM public.organizations o
      JOIN public.organization_public_profiles p ON p.organization_id = o.id
      WHERE o.status = 'active' #{live}
        AND p.published_at IS NOT NULL
        AND (o.slug = box_slug
             OR o.id = (SELECT a.organization_id
                        FROM public.organization_slug_aliases a
                        WHERE a.slug = box_slug))
      LIMIT 1
    $function$
    """)

    execute("""
    CREATE OR REPLACE FUNCTION palee_public_boxes(org_ids uuid[])
     RETURNS TABLE(organization_id uuid, slug text, name text, logo_url text, primary_color text)
     LANGUAGE sql
     STABLE SECURITY DEFINER
     SET search_path TO 'public', 'pg_temp'
    AS $function$
      SELECT o.id, o.slug::text, COALESCE(NULLIF(btrim(s.brand_name), ''), o.name)::text,
             s.brand_logo_url::text, s.brand_primary_color::text
      FROM public.organizations o
      JOIN public.organization_public_profiles p ON p.organization_id = o.id
      LEFT JOIN public.organization_settings s ON s.organization_id = o.id
      WHERE o.id = ANY (org_ids)
        AND o.status = 'active' #{live}
        AND p.published_at IS NOT NULL
    $function$
    """)

    execute("""
    CREATE OR REPLACE FUNCTION palee_referral_invite(invite_code text)
     RETURNS TABLE(code_id uuid, organization_id uuid, user_id uuid, slug text, name text, logo_url text, primary_color text, published boolean)
     LANGUAGE sql
     STABLE SECURITY DEFINER
     SET search_path TO 'public', 'pg_temp'
    AS $function$
      SELECT c.id, c.organization_id, c.user_id, o.slug::text,
             COALESCE(NULLIF(btrim(s.brand_name), ''), o.name)::text,
             s.brand_logo_url::text, s.brand_primary_color::text,
             (p.published_at IS NOT NULL)
      FROM public.referral_codes c
      JOIN public.organizations o ON o.id = c.organization_id
      JOIN public.organization_memberships m
        ON m.organization_id = c.organization_id AND m.user_id = c.user_id
      LEFT JOIN public.organization_settings s ON s.organization_id = o.id
      LEFT JOIN public.organization_public_profiles p ON p.organization_id = o.id
      WHERE c.code = invite_code
        AND c.revoked_at IS NULL
        AND o.status = 'active' #{live}
        AND m.status = 'active'
      LIMIT 1
    $function$
    """)

    execute("""
    CREATE OR REPLACE FUNCTION palee_around_host_places(p_origin geography, p_radius_m double precision, p_bbox geography)
     RETURNS TABLE(organization_id uuid, location_id uuid, latitude double precision, longitude double precision, neighbourhood text, city text, distance_m double precision)
     LANGUAGE sql
     STABLE PARALLEL SAFE
    AS $function$
      SELECT DISTINCT ON (l.organization_id)
             l.organization_id, l.id, l.latitude, l.longitude, l.neighbourhood::text, l.city::text,
             ST_Distance(palee_geo_point(l.latitude, l.longitude), p_origin)
      FROM public.facility_locations l
      JOIN public.organizations o ON o.id = l.organization_id AND o.status = 'active' #{live}
      WHERE l.latitude IS NOT NULL AND l.archived_at IS NULL
        AND palee_geo_point(l.latitude, l.longitude) && p_bbox
        AND ST_DWithin(palee_geo_point(l.latitude, l.longitude), p_origin, p_radius_m)
      ORDER BY l.organization_id, 7, l.id
    $function$
    """)

    execute("""
    CREATE OR REPLACE FUNCTION palee_around_match_events(p_origin geography, p_radius_m double precision, p_bbox geography, p_now_at timestamp with time zone, p_win_from timestamp with time zone[], p_win_to timestamp with time zone[], p_max_price_cents integer, p_disciplines text[], p_audiences text[], p_languages text[], p_amenities text[], p_created_after timestamp with time zone)
     RETURNS TABLE(id uuid, organization_id uuid, latitude double precision, longitude double precision, distance_m double precision, starts_at timestamp with time zone, created_at timestamp with time zone, title text)
     LANGUAGE sql
     STABLE PARALLEL SAFE
    AS $function$
      SELECT e.id, e.organization_id, placed.latitude, placed.longitude, placed.distance_m,
             e.starts_at, e.inserted_at, e.title::text
      FROM (
        SELECT pe.id, pe.latitude, pe.longitude,
               ST_Distance(palee_geo_point(pe.latitude, pe.longitude), p_origin) AS distance_m
        FROM public.community_events pe
        WHERE pe.open_to_non_members AND pe.cancelled_at IS NULL AND pe.latitude IS NOT NULL
          AND palee_geo_point(pe.latitude, pe.longitude) && p_bbox
          AND ST_DWithin(palee_geo_point(pe.latitude, pe.longitude), p_origin, p_radius_m)
          AND pe.starts_at >= p_now_at
        UNION ALL
        SELECT le.id, l.latitude, l.longitude,
               ST_Distance(palee_geo_point(l.latitude, l.longitude), p_origin)
        FROM public.facility_locations l
        JOIN public.community_events le
          ON le.location_id = l.id AND le.organization_id = l.organization_id
        WHERE l.latitude IS NOT NULL AND l.archived_at IS NULL
          AND palee_geo_point(l.latitude, l.longitude) && p_bbox
          AND ST_DWithin(palee_geo_point(l.latitude, l.longitude), p_origin, p_radius_m)
          AND le.open_to_non_members AND le.cancelled_at IS NULL AND le.location_id IS NOT NULL
          AND le.latitude IS NULL AND le.starts_at >= p_now_at
        UNION ALL
        SELECT he.id, h.latitude, h.longitude, h.distance_m
        FROM public.palee_around_host_places(p_origin, p_radius_m, p_bbox) h
        JOIN public.community_events he ON he.organization_id = h.organization_id
        WHERE he.open_to_non_members AND he.cancelled_at IS NULL
          AND he.latitude IS NULL AND he.location_id IS NULL AND he.starts_at >= p_now_at
      ) placed
      JOIN public.community_events e ON e.id = placed.id
      JOIN public.organizations o ON o.id = e.organization_id AND o.status = 'active' #{live}
      LEFT JOIN public.organization_public_profiles pr
        ON pr.organization_id = e.organization_id AND pr.published_at IS NOT NULL
      WHERE (p_win_from IS NULL OR EXISTS (
               SELECT 1 FROM unnest(p_win_from, p_win_to) AS w(f, t)
               WHERE e.starts_at >= w.f AND e.starts_at < w.t))
        AND (p_max_price_cents IS NULL OR e.price_cents <= p_max_price_cents)
        AND (p_created_after IS NULL OR e.inserted_at > p_created_after)
        AND palee_around_tags_match(pr.published_snapshot, p_disciplines, p_audiences, p_languages, p_amenities)
    $function$
    """)
  end
end
