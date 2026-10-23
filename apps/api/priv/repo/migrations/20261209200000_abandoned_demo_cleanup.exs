defmodule Palee.Repo.Migrations.AbandonedDemoCleanup do
  @moduledoc """
  ADR-184 follow-up (TD-184 (4)): abandoned demo businesses get a reminder
  and are then archived.

  - `organizations.demo_last_active_at`: the demo's last activity, the latest
    of its owners' and admins' sign-ins and their console requests (touched
    at most once per configured interval). Backfilled for demos from the
    later of `demo_started_at` and their newest demo record.
  - `organizations.demo_reminder_sent_at`: the claim of the one-time
    reminder. Activity clears it, so a later idle spell reminds again.
  - `organizations.demo_archived_at`: set when the sweep archived the demo;
    only such a demo can be reopened by its owner.
  - Narrow SECURITY DEFINER functions for every write of this lifecycle, so
    none depends on the organizations policies:
    `palee_touch_demo_activity/3` (the acting owner or admin),
    `palee_idle_demo_organizations/1`, `palee_claim_demo_reminder/3`,
    `palee_mark_demo_archived/4` (system sessions and vendors),
    `palee_archived_demo_businesses/0` and `palee_reopen_demo_business/2`
    (the acting owner).
  - Notification type `business_demo_idle`.
  """

  use Ecto.Migration

  @acting_user "NULLIF(current_setting('app.user_id', true), '')::uuid"
  @notification_types ~w(business_demo_idle)
  @last_active "COALESCE(o.demo_last_active_at, o.demo_started_at, o.inserted_at)"
  @staff_roles "ARRAY['owner', 'admin']::varchar[]"

  @functions [
    "palee_touch_demo_activity(uuid, timestamp, integer)",
    "palee_idle_demo_organizations(timestamp)",
    "palee_claim_demo_reminder(uuid, timestamp, timestamp)",
    "palee_mark_demo_archived(uuid, timestamp, timestamp, timestamp)",
    "palee_archived_demo_businesses()",
    "palee_reopen_demo_business(uuid, timestamp)"
  ]

  def up do
    alter table(:organizations) do
      add :demo_last_active_at, :utc_datetime_usec
      add :demo_reminder_sent_at, :utc_datetime_usec
      add :demo_archived_at, :utc_datetime_usec
    end

    create constraint(:organizations, :organizations_demo_archived_check,
             check: "demo_archived_at IS NULL OR activation = 'demo'"
           )

    create index(:organizations, [:demo_last_active_at],
             where: "activation = 'demo' AND status = 'active'",
             name: :organizations_idle_demo_index
           )

    execute("""
    UPDATE organizations o
    SET demo_last_active_at = GREATEST(
          COALESCE(o.demo_started_at, o.inserted_at),
          (SELECT max(d.inserted_at) FROM demo_records d WHERE d.organization_id = o.id))
    WHERE o.activation = 'demo'
    """)

    create_functions()
    add_notification_types(@notification_types)
  end

  def down do
    execute("DELETE FROM notifications WHERE type IN (#{in_list(@notification_types)})")
    remove_notification_types(@notification_types)

    for function <- @functions, do: execute("DROP FUNCTION IF EXISTS #{function}")

    drop index(:organizations, [:demo_last_active_at], name: :organizations_idle_demo_index)
    drop constraint(:organizations, :organizations_demo_archived_check)

    alter table(:organizations) do
      remove :demo_archived_at
      remove :demo_reminder_sent_at
      remove :demo_last_active_at
    end
  end

  defp create_functions do
    # The acting account's activity in its demo businesses (one, or every one
    # it runs when `p_org` is NULL, i.e. at sign-in). Written at most once per
    # `p_interval_seconds`, but always when a reminder was claimed, since
    # activity withdraws it.
    execute("""
    CREATE OR REPLACE FUNCTION palee_touch_demo_activity(
      p_org uuid, p_now timestamp, p_interval_seconds integer)
    RETURNS integer
    LANGUAGE plpgsql
    VOLATILE
    SECURITY DEFINER
    SET search_path = public, pg_temp
    AS $$
    DECLARE
      v_user uuid := #{@acting_user};
      v_count integer;
    BEGIN
      IF v_user IS NULL THEN
        RETURN 0;
      END IF;

      UPDATE public.organizations o
      SET demo_last_active_at = p_now, demo_reminder_sent_at = NULL
      WHERE o.activation = 'demo' AND o.status = 'active'
        AND (p_org IS NULL OR o.id = p_org)
        AND (o.demo_last_active_at IS NULL
             OR o.demo_last_active_at < p_now - make_interval(secs => p_interval_seconds)
             OR o.demo_reminder_sent_at IS NOT NULL)
        AND EXISTS (
          SELECT 1 FROM public.organization_memberships m
          WHERE m.organization_id = o.id AND m.user_id = v_user AND m.status = 'active'
            AND m.roles && #{@staff_roles});

      GET DIAGNOSTICS v_count = ROW_COUNT;
      RETURN v_count;
    END
    $$
    """)

    # The sweep: demo businesses idle since before `p_before`, with their
    # owners (never a mock person). System sessions and vendors only.
    execute("""
    CREATE OR REPLACE FUNCTION palee_idle_demo_organizations(p_before timestamp)
    RETURNS TABLE(organization_id uuid, last_active_at timestamp,
                  reminder_sent_at timestamp, owner_ids uuid[])
    LANGUAGE sql
    STABLE
    SECURITY DEFINER
    SET search_path = public, pg_temp
    AS $$
      SELECT o.id, #{@last_active}, o.demo_reminder_sent_at,
             COALESCE((
               SELECT array_agg(m.user_id ORDER BY m.inserted_at)
               FROM public.organization_memberships m
               WHERE m.organization_id = o.id AND m.status = 'active'
                 AND 'owner' = ANY(m.roles)
                 AND NOT EXISTS (
                   SELECT 1 FROM public.demo_records d
                   WHERE d.organization_id = o.id AND d.source = 'users'
                     AND d.record_id = m.user_id)), ARRAY[]::uuid[])
      FROM public.organizations o
      WHERE o.activation = 'demo' AND o.status = 'active'
        AND #{@last_active} < p_before
        AND (#{@acting_user} IS NULL OR palee_acting_user_is_vendor())
      ORDER BY #{@last_active}
    $$
    """)

    # Claims the one-time reminder of a demo still idle since `p_before`.
    # Returns the last activity it was claimed for (the dedupe key), or NULL
    # when it was already claimed or the owner came back.
    execute("""
    CREATE OR REPLACE FUNCTION palee_claim_demo_reminder(
      p_org uuid, p_before timestamp, p_now timestamp)
    RETURNS timestamp
    LANGUAGE plpgsql
    VOLATILE
    SECURITY DEFINER
    SET search_path = public, pg_temp
    AS $$
    DECLARE
      v_last timestamp;
    BEGIN
      IF #{@acting_user} IS NOT NULL AND NOT palee_acting_user_is_vendor() THEN
        RETURN NULL;
      END IF;

      UPDATE public.organizations o
      SET demo_reminder_sent_at = p_now
      WHERE o.id = p_org AND o.activation = 'demo' AND o.status = 'active'
        AND o.demo_reminder_sent_at IS NULL
        AND #{@last_active} < p_before
      RETURNING #{@last_active} INTO v_last;

      RETURN v_last;
    END
    $$
    """)

    # Archives a demo idle since `p_before` whose reminder was claimed before
    # `p_reminded_before`. True when this call archived it.
    execute("""
    CREATE OR REPLACE FUNCTION palee_mark_demo_archived(
      p_org uuid, p_before timestamp, p_reminded_before timestamp, p_now timestamp)
    RETURNS boolean
    LANGUAGE plpgsql
    VOLATILE
    SECURITY DEFINER
    SET search_path = public, pg_temp
    AS $$
    BEGIN
      IF #{@acting_user} IS NOT NULL AND NOT palee_acting_user_is_vendor() THEN
        RETURN false;
      END IF;

      UPDATE public.organizations o
      SET status = 'archived', demo_archived_at = p_now, updated_at = p_now
      WHERE o.id = p_org AND o.activation = 'demo' AND o.status = 'active'
        AND #{@last_active} < p_before
        AND o.demo_reminder_sent_at IS NOT NULL
        AND o.demo_reminder_sent_at < p_reminded_before;

      RETURN FOUND;
    END
    $$
    """)

    # The acting owner's demo businesses the sweep archived.
    execute("""
    CREATE OR REPLACE FUNCTION palee_archived_demo_businesses()
    RETURNS TABLE(id uuid, slug text, name text, provider_kind text,
                  demo_archived_at timestamp)
    LANGUAGE sql
    STABLE
    SECURITY DEFINER
    SET search_path = public, pg_temp
    AS $$
      SELECT o.id, o.slug::text, o.name::text, o.provider_kind::text, o.demo_archived_at
      FROM public.organizations o
      JOIN public.organization_memberships m
        ON m.organization_id = o.id AND m.user_id = #{@acting_user}
       AND m.status = 'active' AND 'owner' = ANY(m.roles)
      WHERE o.activation = 'demo' AND o.status = 'archived'
        AND o.demo_archived_at IS NOT NULL
      ORDER BY o.demo_archived_at DESC
    $$
    """)

    # The acting owner reopens an archived demo: active again, empty (the
    # sweep removed its demo data), with a fresh clock and no reminder.
    execute("""
    CREATE OR REPLACE FUNCTION palee_reopen_demo_business(p_org uuid, p_now timestamp)
    RETURNS uuid
    LANGUAGE plpgsql
    VOLATILE
    SECURITY DEFINER
    SET search_path = public, pg_temp
    AS $$
    DECLARE
      v_user uuid := #{@acting_user};
    BEGIN
      UPDATE public.organizations o
      SET status = 'active', demo_archived_at = NULL, demo_reminder_sent_at = NULL,
          demo_last_active_at = p_now, updated_at = p_now
      WHERE o.id = p_org AND o.activation = 'demo' AND o.status = 'archived'
        AND o.demo_archived_at IS NOT NULL AND v_user IS NOT NULL
        AND EXISTS (
          SELECT 1 FROM public.organization_memberships m
          WHERE m.organization_id = o.id AND m.user_id = v_user AND m.status = 'active'
            AND 'owner' = ANY(m.roles));

      -- NULL rather than an error, so the caller's transaction stays usable.
      IF NOT FOUND THEN
        RETURN NULL;
      END IF;

      RETURN p_org;
    END
    $$
    """)
  end

  defp add_notification_types(types), do: rewrite_notification_types(&Enum.uniq(&1 ++ types))
  defp remove_notification_types(types), do: rewrite_notification_types(&(&1 -- types))

  defp rewrite_notification_types(change) do
    flush()

    %{rows: [[definition]]} =
      repo().query!("""
      SELECT pg_get_constraintdef(oid) FROM pg_constraint
      WHERE conname = 'notifications_type_check' AND conrelid = 'notifications'::regclass
      """)

    current = Regex.scan(~r/'([a-z0-9_]+)'/, definition) |> Enum.map(&List.last/1)

    execute("ALTER TABLE notifications DROP CONSTRAINT notifications_type_check")

    execute(
      "ALTER TABLE notifications ADD CONSTRAINT notifications_type_check CHECK (type IN (#{in_list(change.(current))}))"
    )
  end

  defp in_list(types), do: Enum.map_join(types, ", ", &"'#{&1}'")
end
