defmodule Palee.Repo.Migrations.EventOrganisersAndCohosts do
  @moduledoc """
  ADR-185 (M2): event organisers, co-hosting and the organiser Events console.

  - `organizations.provider_kind` gains `organiser`: the one-person
    organisation «Ως εγώ» creates on first use, so a person's own events
    reuse the tenant model (RLS, attendees, check-in, messages). Its default
    platform plan is the free, hidden `organiser` plan.
  - `community_events.audience` (`group` | `club` | `open`) says who an event
    is for. A member group's admin now picks price, audience and guest
    passes like any host (ADR-153 §13 lifted): the `community_events_group_check`
    constraint goes. `open_to_non_members` stays and wins: an event open to
    everyone is `open` whatever the column says (the app keeps the two in
    step); `group` needs a group and is never open.
  - `community_event_cohosts`: one host organisation plus co-host
    organisations per event, by request and accept. Rows live in the host's
    tenant; the co-host's side reads and answers them only through narrow
    SECURITY DEFINER functions (ADR-131 §2, ADR-154 §5), never by loosening
    the tenant policy.
  - Attendee refunds (`refunded_at`, `refund_cents`, `refunded_by_id`) for
    the console's Οικονομικά.
  - `community_event_view_days` (aggregated opens and distinct viewers per
    event and day) and `community_event_view_marks` (a per-day keyed hash
    that dedupes a viewer; never a user id, purged after the day).
  - Profile posts may carry an `event` attachment: a person's own event's
    card goes to their followers' feeds.
  - Notifications: `community_event_cohost_request`, `community_event_cohost_answered`.
  """

  use Ecto.Migration

  @me "NULLIF(current_setting('app.user_id', true), '')::uuid"
  @types ~w(community_event_cohost_request community_event_cohost_answered)

  def up do
    organiser_kind()
    audience()
    cohosts()
    refunds()
    views()
    profile_event_cards()
    add_notification_types(@types)
  end

  def down do
    execute("DELETE FROM notifications WHERE type IN (#{in_list(@types)})")
    remove_notification_types(@types)

    execute("DELETE FROM community_profile_posts WHERE attachment_type = 'event'")
    profile_attachment_check(~w(training_log_entry workout_execution pr))

    drop table(:community_event_view_marks)
    drop table(:community_event_view_days)

    drop constraint(:community_event_attendees, :community_event_attendees_refund_check)

    alter table(:community_event_attendees) do
      remove :refunded_at
      remove :refund_cents
      remove :refunded_by_id
    end

    execute("DROP POLICY community_events_cohost_read_policy ON community_events")

    for function <- [
          "palee_acting_user_cohosted_event_ids()",
          "palee_event_cohost_requests(uuid)",
          "palee_respond_event_cohost(uuid, text, timestamp)",
          "palee_accepted_event_cohosts(uuid[], uuid[])",
          "palee_event_cohosted_by(uuid, uuid)",
          "palee_cohost_trial_offer_facts(uuid)",
          "palee_claim_cohost_trial_offer(uuid, timestamp)",
          "palee_event_host_kinds(uuid[])",
          "palee_acting_user_runs_events(uuid)",
          "palee_empty_organiser_organization_ids(timestamp)"
        ] do
      execute("DROP FUNCTION IF EXISTS #{function}")
    end

    drop table(:community_event_cohosts)

    execute("DROP POLICY community_events_member_read_policy ON community_events")

    execute("""
    CREATE POLICY community_events_member_read_policy ON community_events
    FOR SELECT
    USING (
      palee_acting_user_belongs_to(organization_id)
      AND (
        channel_id IS NULL
        OR channel_id IN (SELECT palee_acting_user_group_ids())
        OR palee_acting_user_administers(organization_id)
        OR palee_acting_user_coaches(organization_id)
      )
    )
    """)

    drop constraint(:community_events, :community_events_audience_check)

    execute("""
    UPDATE community_events
    SET price_cents = 0, open_to_non_members = false, guest_pass_allowed = false,
        good_for_friends = false
    WHERE channel_id IS NOT NULL
    """)

    alter table(:community_events) do
      remove :audience
    end

    create constraint(:community_events, :community_events_group_check,
             check:
               "channel_id IS NULL OR (price_cents = 0 AND NOT open_to_non_members AND NOT guest_pass_allowed)"
           )

    execute("DELETE FROM organization_platform_subscriptions WHERE plan_code = 'organiser'")
    execute("DELETE FROM platform_plans WHERE code = 'organiser'")
    drop constraint(:platform_plans, :platform_plans_audience_check)

    create constraint(:platform_plans, :platform_plans_audience_check,
             check: "audience IN ('gym', 'coach')"
           )

    execute("UPDATE organizations SET status = 'archived' WHERE provider_kind = 'organiser'")
    execute("UPDATE organizations SET provider_kind = 'coach' WHERE provider_kind = 'organiser'")
    drop index(:organizations, [:inserted_at], name: :organizations_organiser_index)
    drop constraint(:organizations, :organizations_provider_kind_check)

    create constraint(:organizations, :organizations_provider_kind_check,
             check: "provider_kind IN ('gym', 'coach')"
           )
  end

  # ------------------------------------------------------------------ organiser kind

  defp organiser_kind do
    drop constraint(:organizations, :organizations_provider_kind_check)

    create constraint(:organizations, :organizations_provider_kind_check,
             check: "provider_kind IN ('gym', 'coach', 'organiser')"
           )

    # One organiser organisation per person is enforced by the command under
    # an advisory lock; this index makes the cleanup and lookup cheap.
    create index(:organizations, [:inserted_at],
             where: "provider_kind = 'organiser'",
             name: :organizations_organiser_index
           )

    drop constraint(:platform_plans, :platform_plans_audience_check)

    create constraint(:platform_plans, :platform_plans_audience_check,
             check: "audience IN ('gym', 'coach', 'organiser')"
           )

    execute("""
    INSERT INTO platform_plans
      (id, code, audience, name, description, limits, monthly_price_cents,
       annual_price_cents, currency, price_status, trial_days, is_default,
       public, active, position, inserted_at, updated_at)
    VALUES
      (gen_random_uuid(), 'organiser', 'organiser', 'Organiser',
       'A person hosting their own events: free, one seat, nothing to set up.',
       '{"staff_seats": 1}'::jsonb, 0, 0, 'EUR', 'confirmed', 0, true, false, true, 30,
       now(), now())
    ON CONFLICT (code) DO NOTHING
    """)

    # ADR-185 §1: who runs events at an organisation (manage_events: owner,
    # admin, coach), from the acting person's own active membership.
    execute("""
    CREATE OR REPLACE FUNCTION palee_acting_user_runs_events(org_id uuid)
    RETURNS boolean
    LANGUAGE sql
    STABLE
    SECURITY DEFINER
    SET search_path = public, pg_temp
    AS $$
      SELECT EXISTS (
        SELECT 1 FROM public.organization_memberships om
        WHERE om.organization_id = org_id
          AND om.user_id = #{@me}
          AND om.status = 'active'
          AND (om.role IN ('owner', 'admin', 'coach')
               OR om.roles && ARRAY['owner', 'admin', 'coach']::varchar[])
      )
    $$
    """)

    # The provider kind of event hosts (a person's own events show the person).
    execute("""
    CREATE OR REPLACE FUNCTION palee_event_host_kinds(p_organization_ids uuid[])
    RETURNS TABLE (organization_id uuid, provider_kind text)
    LANGUAGE sql
    STABLE
    SECURITY DEFINER
    SET search_path = public, pg_temp
    AS $$
      SELECT o.id, o.provider_kind::text FROM public.organizations o
      WHERE o.id = ANY (p_organization_ids)
    $$
    """)

    # ADR-185 §9: organiser organisations that never got an event, for the
    # daily cleanup (ids only).
    execute("""
    CREATE OR REPLACE FUNCTION palee_empty_organiser_organization_ids(p_before timestamp)
    RETURNS SETOF uuid
    LANGUAGE sql
    STABLE
    SECURITY DEFINER
    SET search_path = public, pg_temp
    AS $$
      SELECT o.id FROM public.organizations o
      WHERE o.provider_kind = 'organiser' AND o.status = 'active'
        AND o.inserted_at < p_before
        AND NOT EXISTS (SELECT 1 FROM public.community_events e WHERE e.organization_id = o.id)
    $$
    """)
  end

  # ------------------------------------------------------------------ audience

  defp audience do
    alter table(:community_events) do
      add :audience, :text, null: false, default: "club"
    end

    execute("UPDATE community_events SET audience = 'open' WHERE open_to_non_members")

    execute(
      "UPDATE community_events SET audience = 'group' WHERE channel_id IS NOT NULL AND NOT open_to_non_members"
    )

    drop constraint(:community_events, :community_events_group_check)

    create constraint(:community_events, :community_events_audience_check,
             check:
               "audience IN ('group', 'club', 'open') AND " <>
                 "(audience <> 'open' OR open_to_non_members) AND " <>
                 "(audience <> 'group' OR (channel_id IS NOT NULL AND NOT open_to_non_members))"
           )

    # A group event for the whole club (or everyone) reads like a club event;
    # one for the group only still reads for its members and the box's staff.
    execute("DROP POLICY community_events_member_read_policy ON community_events")

    execute("""
    CREATE POLICY community_events_member_read_policy ON community_events
    FOR SELECT
    USING (
      palee_acting_user_belongs_to(organization_id)
      AND (
        channel_id IS NULL
        OR audience <> 'group'
        OR channel_id IN (SELECT palee_acting_user_group_ids())
        OR palee_acting_user_administers(organization_id)
        OR palee_acting_user_coaches(organization_id)
      )
    )
    """)
  end

  # ------------------------------------------------------------------ co-hosts

  defp cohosts do
    create table(:community_event_cohosts, primary_key: false) do
      add :id, :binary_id, primary_key: true

      # The host's tenant: the row belongs to the event's organisation.
      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :event_id, :binary_id, null: false

      add :cohost_organization_id,
          references(:organizations, type: :binary_id, on_delete: :delete_all),
          null: false

      add :status, :text, null: false, default: "pending"
      add :invited_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :responded_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :responded_at, :utc_datetime_usec
      add :trial_offer_sent_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    execute("""
    ALTER TABLE community_event_cohosts
    ADD CONSTRAINT community_event_cohosts_event_id_fkey
    FOREIGN KEY (event_id, organization_id)
    REFERENCES community_events (id, organization_id) ON DELETE CASCADE
    """)

    create constraint(:community_event_cohosts, :community_event_cohosts_status_check,
             check: "status IN ('pending', 'accepted', 'declined', 'removed')"
           )

    create constraint(:community_event_cohosts, :community_event_cohosts_self_check,
             check: "cohost_organization_id <> organization_id"
           )

    create constraint(:community_event_cohosts, :community_event_cohosts_answer_check,
             check: "(status = 'pending') = (responded_at IS NULL)"
           )

    create unique_index(:community_event_cohosts, [:event_id, :cohost_organization_id])
    create index(:community_event_cohosts, [:cohost_organization_id, :status])

    # The tenant stamp runs on insert only: the co-host answers through a
    # definer function from its own tenant, and an update stamp would move
    # the row there. The tenant policy still checks every host-side write.
    execute("""
    CREATE TRIGGER community_event_cohosts_apply_tenant_context
    BEFORE INSERT ON community_event_cohosts
    FOR EACH ROW EXECUTE FUNCTION palee_apply_tenant_context()
    """)

    secure_without_timestamps("community_event_cohosts")

    staff = "palee_acting_user_runs_events(c.cohost_organization_id)"

    # A person's session reads the events co-hosted (accepted) by a box they
    # belong to, unless the event is for a member group only.
    execute("""
    CREATE OR REPLACE FUNCTION palee_acting_user_cohosted_event_ids()
    RETURNS SETOF uuid
    LANGUAGE sql
    STABLE
    SECURITY DEFINER
    SET search_path = public, pg_temp
    AS $$
      SELECT c.event_id
      FROM public.community_event_cohosts c
      JOIN public.organization_memberships m
        ON m.organization_id = c.cohost_organization_id
       AND m.user_id = #{@me} AND m.status = 'active'
      WHERE c.status = 'accepted'
    $$
    """)

    execute("""
    CREATE POLICY community_events_cohost_read_policy ON community_events
    FOR SELECT
    USING (audience <> 'group' AND id IN (SELECT palee_acting_user_cohosted_event_ids()))
    """)

    # The co-host's inbox: requests to a box, for whoever runs its events.
    execute("""
    CREATE OR REPLACE FUNCTION palee_event_cohost_requests(p_organization_id uuid)
    RETURNS TABLE (
      id uuid, event_id uuid, host_organization_id uuid, status text,
      invited_by_id uuid, inserted_at timestamp, responded_at timestamp,
      trial_offer_sent_at timestamp, title text, starts_at timestamp, ends_at timestamp,
      time_zone text, cancelled_at timestamp, series_id uuid, audience text,
      created_by_id uuid, host_name text, host_slug text, host_kind text
    )
    LANGUAGE sql
    STABLE
    SECURITY DEFINER
    SET search_path = public, pg_temp
    AS $$
      SELECT c.id, c.event_id, c.organization_id, c.status::text, c.invited_by_id,
             c.inserted_at, c.responded_at, c.trial_offer_sent_at,
             e.title::text, e.starts_at, e.ends_at, e.time_zone::text, e.cancelled_at,
             e.series_id, e.audience::text, e.created_by_id,
             o.name::text, o.slug::text, o.provider_kind::text
      FROM public.community_event_cohosts c
      JOIN public.community_events e ON e.id = c.event_id
      JOIN public.organizations o ON o.id = c.organization_id
      WHERE c.cohost_organization_id = p_organization_id
        AND #{staff}
      ORDER BY e.starts_at, c.id
      LIMIT 500
    $$
    """)

    # Accept or decline a request (and every later pending occurrence of the
    # same weekly event for the same box), or withdraw an accepted co-host.
    execute("""
    CREATE OR REPLACE FUNCTION palee_respond_event_cohost(p_id uuid, p_status text, p_now timestamp)
    RETURNS TABLE (id uuid, event_id uuid, organization_id uuid, status text)
    LANGUAGE plpgsql
    VOLATILE
    SECURITY DEFINER
    SET search_path = public, pg_temp
    AS $$
    DECLARE
      v_row public.community_event_cohosts%ROWTYPE;
      v_event public.community_events%ROWTYPE;
    BEGIN
      SELECT * INTO v_row FROM public.community_event_cohosts c WHERE c.id = p_id FOR UPDATE;

      IF NOT FOUND OR NOT palee_acting_user_runs_events(v_row.cohost_organization_id) THEN
        RETURN;
      END IF;

      IF NOT ((v_row.status = 'pending' AND p_status IN ('accepted', 'declined'))
              OR (v_row.status = 'accepted' AND p_status = 'removed')) THEN
        RETURN;
      END IF;

      SELECT * INTO v_event FROM public.community_events e WHERE e.id = v_row.event_id;

      RETURN QUERY
      UPDATE public.community_event_cohosts c
      SET status = p_status, responded_by_id = #{@me},
          responded_at = COALESCE(c.responded_at, p_now), updated_at = p_now
      FROM public.community_events e
      WHERE e.id = c.event_id
        AND c.cohost_organization_id = v_row.cohost_organization_id
        AND c.status = v_row.status
        AND (
          c.id = v_row.id
          OR (v_event.series_id IS NOT NULL AND e.series_id = v_event.series_id
              AND e.starts_at >= v_event.starts_at)
        )
      RETURNING c.id, c.event_id, c.organization_id, c.status::text;
    END
    $$
    """)

    # Accepted co-hosts by event or by co-host (ids only: who co-hosts what).
    execute("""
    CREATE OR REPLACE FUNCTION palee_accepted_event_cohosts(p_event_ids uuid[], p_cohost_ids uuid[])
    RETURNS TABLE (event_id uuid, host_organization_id uuid, cohost_organization_id uuid)
    LANGUAGE sql
    STABLE
    SECURITY DEFINER
    SET search_path = public, pg_temp
    AS $$
      SELECT c.event_id, c.organization_id, c.cohost_organization_id
      FROM public.community_event_cohosts c
      WHERE c.status = 'accepted'
        AND (p_event_ids IS NULL OR c.event_id = ANY (p_event_ids))
        AND (p_cohost_ids IS NULL OR c.cohost_organization_id = ANY (p_cohost_ids))
      LIMIT 2000
    $$
    """)

    execute("""
    CREATE OR REPLACE FUNCTION palee_event_cohosted_by(p_event_id uuid, p_organization_id uuid)
    RETURNS boolean
    LANGUAGE sql
    STABLE
    SECURITY DEFINER
    SET search_path = public, pg_temp
    AS $$
      SELECT EXISTS (
        SELECT 1 FROM public.community_event_cohosts c
        WHERE c.event_id = p_event_id AND c.cohost_organization_id = p_organization_id
          AND c.status = 'accepted'
      )
    $$
    """)

    # What a co-host's staff need for its own trial offer: the event's times
    # and the people who came. The rules are applied in Elixir (EventPolicy).
    execute("""
    CREATE OR REPLACE FUNCTION palee_cohost_trial_offer_facts(p_id uuid)
    RETURNS TABLE (
      event_id uuid, host_organization_id uuid, cohost_organization_id uuid, status text,
      club_id uuid, title text, starts_at timestamp, ends_at timestamp, time_zone text,
      cancelled_at timestamp, trial_offer_sent_at timestamp, came_user_ids uuid[]
    )
    LANGUAGE sql
    STABLE
    SECURITY DEFINER
    SET search_path = public, pg_temp
    AS $$
      SELECT c.event_id, c.organization_id, c.cohost_organization_id, c.status::text,
             e.club_id, e.title::text, e.starts_at, e.ends_at, e.time_zone::text,
             e.cancelled_at, c.trial_offer_sent_at,
             COALESCE(
               (SELECT array_agg(a.user_id ORDER BY a.queued_at)
                FROM public.community_event_attendees a
                WHERE a.event_id = c.event_id AND a.status = 'going'
                  AND a.checked_in_at IS NOT NULL),
               ARRAY[]::uuid[]
             )
      FROM public.community_event_cohosts c
      JOIN public.community_events e ON e.id = c.event_id
      WHERE c.id = p_id AND #{staff}
    $$
    """)

    execute("""
    CREATE OR REPLACE FUNCTION palee_claim_cohost_trial_offer(p_id uuid, p_now timestamp)
    RETURNS boolean
    LANGUAGE plpgsql
    VOLATILE
    SECURITY DEFINER
    SET search_path = public, pg_temp
    AS $$
    BEGIN
      UPDATE public.community_event_cohosts c
      SET trial_offer_sent_at = p_now, updated_at = p_now
      WHERE c.id = p_id AND c.status = 'accepted' AND c.trial_offer_sent_at IS NULL
        AND #{staff};
      RETURN FOUND;
    END
    $$
    """)
  end

  # ------------------------------------------------------------------ refunds

  defp refunds do
    alter table(:community_event_attendees) do
      add :refunded_at, :utc_datetime_usec
      add :refund_cents, :integer
      add :refunded_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
    end

    create constraint(:community_event_attendees, :community_event_attendees_refund_check,
             check:
               "(refunded_at IS NULL) = (refund_cents IS NULL) AND " <>
                 "(refunded_at IS NULL OR paid_at IS NOT NULL) AND " <>
                 "(refund_cents IS NULL OR (refund_cents > 0 AND refund_cents <= COALESCE(amount_cents, 0)))"
           )
  end

  # ------------------------------------------------------------------ views

  defp views do
    # A surrogate `id` lets tenant export and purge (ADR-117) treat them like
    # every other table; the natural keys stay unique.
    create table(:community_event_view_days, primary_key: false) do
      add :id, :binary_id, primary_key: true, default: fragment("gen_random_uuid()")

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :event_id, :binary_id, null: false
      add :day, :date, null: false
      add :views, :integer, null: false, default: 0
      add :viewers, :integer, null: false, default: 0
    end

    create unique_index(:community_event_view_days, [:event_id, :day])

    create table(:community_event_view_marks, primary_key: false) do
      add :id, :binary_id, primary_key: true, default: fragment("gen_random_uuid()")

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :event_id, :binary_id, null: false
      add :day, :date, null: false
      # HMAC of (event, day, viewer) with a server key: unlinkable across
      # events and days, and dropped once the day is over.
      add :viewer_key, :binary, null: false
    end

    create unique_index(:community_event_view_marks, [:event_id, :day, :viewer_key])

    for table <- ~w(community_event_view_days community_event_view_marks) do
      execute("""
      ALTER TABLE #{table}
      ADD CONSTRAINT #{table}_event_id_fkey
      FOREIGN KEY (event_id, organization_id)
      REFERENCES community_events (id, organization_id) ON DELETE CASCADE
      """)

      secure_without_timestamps(table)
    end

    create constraint(:community_event_view_days, :community_event_view_days_counts_check,
             check: "views >= 0 AND viewers >= 0 AND viewers <= views"
           )

    create index(:community_event_view_days, [:organization_id, :day])
  end

  # ------------------------------------------------------------------ profile cards

  defp profile_event_cards,
    do: profile_attachment_check(~w(training_log_entry workout_execution pr event))

  defp profile_attachment_check(types) do
    execute(
      "ALTER TABLE community_profile_posts DROP CONSTRAINT community_profile_posts_attachment_check"
    )

    create constraint(:community_profile_posts, :community_profile_posts_attachment_check,
             check:
               "(attachment_type IS NULL AND attachment_id IS NULL AND attachment IS NULL) OR " <>
                 "(attachment_type IN (#{in_list(types)}) AND attachment_id IS NOT NULL AND attachment IS NOT NULL)"
           )
  end

  # ------------------------------------------------------------------ helpers

  defp secure_without_timestamps(table) do
    execute("""
    CREATE POLICY #{table}_tenant_policy ON #{table}
    USING (organization_id = NULLIF(current_setting('app.organization_id', true), '')::uuid)
    WITH CHECK (organization_id = NULLIF(current_setting('app.organization_id', true), '')::uuid)
    """)

    execute("ALTER TABLE #{table} ENABLE ROW LEVEL SECURITY")
    execute("ALTER TABLE #{table} FORCE ROW LEVEL SECURITY")
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
