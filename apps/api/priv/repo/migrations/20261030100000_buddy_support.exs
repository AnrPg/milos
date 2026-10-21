defmodule Palee.Repo.Migrations.BuddySupport do
  @moduledoc """
  ADR-160 (P2-M12, Buddy για στήριξη): one or two trusted people who get only
  what the member explicitly sends with «Χρειάζομαι στήριξη», and the
  member's choice to give their coaches a weekly wellness summary.

  Everything here is the person's own (account-scoped, never a gym's): rows
  key on `user_id` (the member who asks for support) and go with the
  account. A buddy is the second party of a row and reads it too.

  - `buddy_links`: requester `user_id`, `buddy_user_id` (null until an
    off-platform invite link is claimed), the link's `invite_token_hash`,
    `status` pending|active|declined|ended|expired, whether the buddy gets
    the weekly counts summary, and who ended it. A pending invite expires
    after 7 days. At most one open (pending or active) link per pair.
  - `buddy_settings`: the person's quiet hours (local `quiet_from` ..
    `quiet_to` in `tz`), and whether buddies may see their phone (off by
    default) for «Πάρε με τηλέφωνο».
  - `support_requests`: one «Χρειάζομαι στήριξη»: an optional message of at
    most 280 characters and its source (craving or quick). `source_ref` is
    an opaque id of the craving it came from; no craving detail is ever
    stored or sent here. `undone_at` for the 5-second undo, `delivered_at`
    once buddies were told, `nudge_sent_at` for the 10-minute gentle card.
  - `support_request_deliveries`: who received it, silently when it was
    their quiet hours, and when they replied.
  - `support_replies`: a buddy's answer (here, walk, call, text) and the
    conversation it opened, if any.
  - `wellness_summary_grants`: the member's «Ευεξία · εβδομαδιαία σύνοψη»
    (`wellness`) and «Λιγούρες στη σύνοψη» (`cravings`) toggles for their
    coaches, one row per grant; a withdrawal closes it.

  Row security: each party reads its rows (`user_id` or `buddy_user_id` is
  the session user); a support request is visible to the buddies it was
  delivered to. Narrow SECURITY DEFINER functions answer what crosses
  people: the relation that makes someone eligible, the people one may
  invite, an invite link's preview and claim, a buddy's quiet hours, a
  requester's phone when shared, and who is due a weekly summary.
  """

  use Ecto.Migration

  @notification_types ~w(
    buddy_invite buddy_accepted support_request support_reply
    support_no_reply_nudge buddy_weekly_summary
  )

  def up do
    create table(:buddy_links, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :buddy_user_id, references(:users, type: :binary_id, on_delete: :delete_all)
      add :invite_token_hash, :binary
      add :status, :string, null: false, default: "pending"
      add :receives_weekly_summary, :boolean, null: false, default: false
      add :expires_at, :utc_datetime_usec
      add :started_at, :utc_datetime_usec
      add :ended_at, :utc_datetime_usec
      add :ended_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime_usec)
    end

    create constraint(:buddy_links, :buddy_links_status_check,
             check: "status IN ('pending', 'active', 'declined', 'ended', 'expired')"
           )

    create constraint(:buddy_links, :buddy_links_party_check,
             check:
               "(buddy_user_id IS NOT NULL OR invite_token_hash IS NOT NULL) " <>
                 "AND buddy_user_id IS DISTINCT FROM user_id"
           )

    create constraint(:buddy_links, :buddy_links_active_check,
             check: "status <> 'active' OR (buddy_user_id IS NOT NULL AND started_at IS NOT NULL)"
           )

    create unique_index(:buddy_links, [:user_id, :buddy_user_id],
             where: "status IN ('pending', 'active') AND buddy_user_id IS NOT NULL",
             name: :buddy_links_open_pair_index
           )

    create unique_index(:buddy_links, [:invite_token_hash],
             where: "invite_token_hash IS NOT NULL"
           )

    create index(:buddy_links, [:user_id, :status])
    create index(:buddy_links, [:buddy_user_id, :status])

    create table(:buddy_settings, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :quiet_from, :time
      add :quiet_to, :time
      add :tz, :string, null: false, default: "Europe/Athens"
      add :share_phone, :boolean, null: false, default: false
      add :phone, :string

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:buddy_settings, [:user_id])

    create constraint(:buddy_settings, :buddy_settings_quiet_check,
             check:
               "(quiet_from IS NULL AND quiet_to IS NULL) OR " <>
                 "(quiet_from IS NOT NULL AND quiet_to IS NOT NULL AND quiet_from <> quiet_to)"
           )

    create constraint(:buddy_settings, :buddy_settings_phone_check,
             check: "phone IS NULL OR phone ~ '^\\+?[0-9 ()-]{6,24}$'"
           )

    create table(:support_requests, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :message, :string, size: 1200
      add :source, :string, null: false, default: "quick"
      add :source_ref, :binary_id
      add :undone_at, :utc_datetime_usec
      add :delivered_at, :utc_datetime_usec
      add :nudge_sent_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create constraint(:support_requests, :support_requests_source_check,
             check: "source IN ('craving', 'quick')"
           )

    create constraint(:support_requests, :support_requests_message_check,
             check: "message IS NULL OR char_length(message) BETWEEN 1 AND 280"
           )

    create index(:support_requests, [:user_id, :inserted_at])

    create table(:support_request_deliveries, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :request_id, references(:support_requests, type: :binary_id, on_delete: :delete_all),
        null: false

      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      add :buddy_user_id, references(:users, type: :binary_id, on_delete: :delete_all),
        null: false

      add :delivered_silently, :boolean, null: false, default: false
      add :replied_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(:support_request_deliveries, [:request_id, :buddy_user_id])
    create index(:support_request_deliveries, [:buddy_user_id, :inserted_at])

    create table(:support_replies, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :request_id, references(:support_requests, type: :binary_id, on_delete: :delete_all),
        null: false

      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      add :buddy_user_id, references(:users, type: :binary_id, on_delete: :delete_all),
        null: false

      add :kind, :string, null: false
      add :text, :string, size: 2000
      add :thread_id, :binary_id
      add :conversation_organization_id, :binary_id

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create constraint(:support_replies, :support_replies_kind_check,
             check: "kind IN ('here', 'walk', 'call', 'text')"
           )

    create constraint(:support_replies, :support_replies_text_check,
             check:
               "(text IS NULL OR char_length(text) BETWEEN 1 AND 500) AND " <>
                 "(kind <> 'text' OR text IS NOT NULL)"
           )

    create index(:support_replies, [:request_id, :inserted_at])

    create table(:wellness_summary_grants, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :scope, :string, null: false
      add :granted_at, :utc_datetime_usec, null: false
      add :withdrawn_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create constraint(:wellness_summary_grants, :wellness_summary_grants_scope_check,
             check: "scope IN ('wellness', 'cravings')"
           )

    create unique_index(:wellness_summary_grants, [:user_id, :scope],
             where: "withdrawn_at IS NULL",
             name: :wellness_summary_grants_active_index
           )

    functions()
    policies()
    add_notification_types(@notification_types)
  end

  def down do
    execute("DELETE FROM notifications WHERE type IN (#{in_list(@notification_types)})")
    remove_notification_types(@notification_types)

    execute("DROP POLICY IF EXISTS support_requests_buddy_read_policy ON support_requests")

    drop table(:wellness_summary_grants)
    drop table(:support_replies)
    drop table(:support_request_deliveries)
    drop table(:support_requests)
    drop table(:buddy_settings)
    drop table(:buddy_links)

    for function <- [
          "palee_buddy_relation(uuid)",
          "palee_buddy_candidates(text, integer)",
          "palee_buddy_invite_preview(bytea, timestamp)",
          "palee_buddy_claim_invite(bytea, timestamp)",
          "palee_buddy_linked(uuid)",
          "palee_buddy_quiet_hours(uuid)",
          "palee_buddy_shared_phone(uuid)",
          "palee_buddy_summary_requesters(integer)"
        ] do
      execute("DROP FUNCTION IF EXISTS #{function}")
    end
  end

  defp functions do
    # Why the session user may ask `other` to be a buddy: `coach` (other
    # coaches them), `club` (an active gym or open club in common) or
    # `follow` (either follows the other); NULL otherwise. One answer about
    # one pair; the rows it reads are invisible to the session.
    execute("""
    CREATE FUNCTION palee_buddy_relation(other uuid)
    RETURNS text
    LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp
    AS $$
      WITH me AS (SELECT NULLIF(current_setting('app.user_id', true), '')::uuid AS id)
      SELECT CASE
        WHEN (SELECT id FROM me) IS NULL OR other IS NULL OR other = (SELECT id FROM me) THEN NULL
        WHEN EXISTS (
          SELECT 1 FROM coaching_relationships r
          WHERE r.coach_user_id = other AND r.client_user_id = (SELECT id FROM me)
            AND r.ended_at IS NULL
        ) THEN 'coach'
        WHEN EXISTS (
          SELECT 1 FROM organization_memberships a
          JOIN organization_memberships b ON b.organization_id = a.organization_id
          WHERE a.user_id = (SELECT id FROM me) AND b.user_id = other
            AND a.status = 'active' AND b.status = 'active'
        ) OR EXISTS (
          SELECT 1 FROM community_club_memberships a
          JOIN community_club_memberships b ON b.club_id = a.club_id
          JOIN community_clubs c ON c.id = a.club_id
          WHERE a.user_id = (SELECT id FROM me) AND b.user_id = other
            AND a.status = 'active' AND b.status = 'active' AND c.archived_at IS NULL
        ) THEN 'club'
        WHEN EXISTS (
          SELECT 1 FROM community_follows f
          WHERE f.target_type = 'user' AND f.status = 'active'
            AND ((f.user_id = (SELECT id FROM me) AND f.target_id = other)
              OR (f.user_id = other AND f.target_id = (SELECT id FROM me)))
        ) THEN 'follow'
        ELSE NULL
      END
    $$
    """)

    # People the session user may invite: their coaches and the people they
    # follow or who follow them; with a search term, also people of a gym or
    # open club in common who did not hide themselves from members. Ids and
    # the relation only.
    execute("""
    CREATE FUNCTION palee_buddy_candidates(term text, lim integer)
    RETURNS TABLE (user_id uuid, relation text)
    LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp
    AS $$
      WITH me AS (SELECT NULLIF(current_setting('app.user_id', true), '')::uuid AS id),
      pattern AS (
        SELECT CASE WHEN term IS NULL OR length(trim(term)) < 2 THEN NULL
          ELSE replace(replace(replace(lower(trim(term)), '\\', '\\\\'), '%', '\\%'), '_', '\\_') || '%'
        END AS p
      ),
      found AS (
        SELECT r.coach_user_id AS user_id, 'coach' AS relation, 1 AS rank
        FROM coaching_relationships r
        WHERE r.client_user_id = (SELECT id FROM me) AND r.ended_at IS NULL
        UNION ALL
        SELECT CASE WHEN f.user_id = (SELECT id FROM me) THEN f.target_id ELSE f.user_id END,
               'follow', 2
        FROM community_follows f
        WHERE f.target_type = 'user' AND f.status = 'active'
          AND (f.user_id = (SELECT id FROM me) OR f.target_id = (SELECT id FROM me))
        UNION ALL
        SELECT b.user_id, 'club', 3
        FROM organization_memberships a
        JOIN organization_memberships b ON b.organization_id = a.organization_id
        WHERE (SELECT p FROM pattern) IS NOT NULL
          AND a.user_id = (SELECT id FROM me) AND a.status = 'active' AND b.status = 'active'
        UNION ALL
        SELECT b.user_id, 'club', 3
        FROM community_club_memberships a
        JOIN community_club_memberships b ON b.club_id = a.club_id
        JOIN community_clubs c ON c.id = a.club_id
        WHERE (SELECT p FROM pattern) IS NOT NULL
          AND a.user_id = (SELECT id FROM me) AND a.status = 'active' AND b.status = 'active'
          AND c.archived_at IS NULL
      ),
      ranked AS (
        SELECT DISTINCT ON (f.user_id) f.user_id, f.relation, f.rank
        FROM found f
        JOIN users u ON u.id = f.user_id
        LEFT JOIN community_social_settings s ON s.user_id = f.user_id
        WHERE f.user_id <> (SELECT id FROM me)
          AND (f.relation <> 'club' OR NOT COALESCE(s.hide_from_members, false))
          AND ((SELECT p FROM pattern) IS NULL
            OR lower(u.nickname) LIKE (SELECT p FROM pattern)
            OR lower(COALESCE(u.display_nickname, '')) LIKE (SELECT p FROM pattern))
        ORDER BY f.user_id, f.rank
      )
      SELECT ranked.user_id, ranked.relation FROM ranked
      ORDER BY ranked.rank, ranked.user_id
      LIMIT LEAST(GREATEST(lim, 1), 50)
    $$
    """)

    # The landing page of an off-platform invite: who invited and whether
    # the link still works. Nothing else about the inviter or the link.
    execute("""
    CREATE FUNCTION palee_buddy_invite_preview(token_hash bytea, p_now timestamp)
    RETURNS TABLE (link_id uuid, inviter_id uuid, status text, expires_at timestamp)
    LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp
    AS $$
      SELECT l.id, l.user_id,
        CASE
          WHEN l.status = 'pending' AND l.buddy_user_id IS NULL AND l.expires_at > p_now
            THEN 'pending'
          WHEN l.status IN ('pending', 'expired') AND l.buddy_user_id IS NULL THEN 'expired'
          ELSE 'unavailable'
        END,
        l.expires_at
      FROM buddy_links l
      WHERE l.invite_token_hash = token_hash
    $$
    """)

    # Claiming an invite link: the signed-in person becomes the buddy and
    # the link starts (they accepted by claiming it). Only an unexpired,
    # unclaimed link, never one's own, never a second open link of the pair.
    execute("""
    CREATE FUNCTION palee_buddy_claim_invite(token_hash bytea, p_now timestamp)
    RETURNS uuid
    LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = public, pg_temp
    AS $$
    DECLARE
      me uuid := NULLIF(current_setting('app.user_id', true), '')::uuid;
      link buddy_links%ROWTYPE;
    BEGIN
      IF me IS NULL THEN
        RETURN NULL;
      END IF;

      SELECT * INTO link FROM buddy_links
      WHERE invite_token_hash = token_hash
      FOR UPDATE;

      IF NOT FOUND OR link.status <> 'pending' OR link.buddy_user_id IS NOT NULL
         OR link.expires_at <= p_now OR link.user_id = me THEN
        RETURN NULL;
      END IF;

      IF EXISTS (
        SELECT 1 FROM buddy_links o
        WHERE o.user_id = link.user_id AND o.buddy_user_id = me
          AND o.status IN ('pending', 'active') AND o.id <> link.id
      ) THEN
        RETURN NULL;
      END IF;

      UPDATE buddy_links
      SET buddy_user_id = me, status = 'active', started_at = p_now,
          expires_at = NULL, updated_at = p_now
      WHERE id = link.id;

      RETURN link.id;
    END
    $$
    """)

    # Whether the session user and `other` are buddies right now, either way.
    execute("""
    CREATE FUNCTION palee_buddy_linked(other uuid)
    RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp
    AS $$
      SELECT EXISTS (
        SELECT 1 FROM buddy_links l
        WHERE l.status = 'active'
          AND ((l.user_id = NULLIF(current_setting('app.user_id', true), '')::uuid
                AND l.buddy_user_id = other)
            OR (l.buddy_user_id = NULLIF(current_setting('app.user_id', true), '')::uuid
                AND l.user_id = other))
      )
    $$
    """)

    # A buddy's quiet hours, for the person they support (nothing else of
    # their settings).
    execute("""
    CREATE FUNCTION palee_buddy_quiet_hours(buddy uuid)
    RETURNS TABLE (quiet_from time, quiet_to time, tz text)
    LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp
    AS $$
      SELECT s.quiet_from, s.quiet_to, s.tz
      FROM buddy_settings s
      WHERE s.user_id = buddy AND palee_buddy_linked(buddy)
    $$
    """)

    # The phone of someone the session user supports, only when they chose
    # to share it with their buddies.
    execute("""
    CREATE FUNCTION palee_buddy_shared_phone(requester uuid)
    RETURNS text
    LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp
    AS $$
      SELECT s.phone
      FROM buddy_settings s
      WHERE s.user_id = requester AND s.share_phone AND s.phone IS NOT NULL
        AND EXISTS (
          SELECT 1 FROM buddy_links l
          WHERE l.status = 'active' AND l.user_id = requester
            AND l.buddy_user_id = NULLIF(current_setting('app.user_id', true), '')::uuid
        )
    $$
    """)

    # People with at least one active buddy who gets the weekly summary,
    # with the zone their week is counted in. Ids only; the job works in
    # each person's session.
    execute("""
    CREATE FUNCTION palee_buddy_summary_requesters(lim integer)
    RETURNS TABLE (user_id uuid, tz text)
    LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp
    AS $$
      SELECT DISTINCT l.user_id, COALESCE(s.tz, 'Europe/Athens')
      FROM buddy_links l
      LEFT JOIN buddy_settings s ON s.user_id = l.user_id
      WHERE l.status = 'active' AND l.receives_weekly_summary
      ORDER BY l.user_id
      LIMIT lim
    $$
    """)
  end

  defp policies do
    for table <- ~w(buddy_links support_request_deliveries support_replies) do
      execute("""
      CREATE POLICY #{table}_party_policy ON #{table}
      USING (
        user_id = NULLIF(current_setting('app.user_id', true), '')::uuid
        OR buddy_user_id = NULLIF(current_setting('app.user_id', true), '')::uuid
      )
      WITH CHECK (
        user_id = NULLIF(current_setting('app.user_id', true), '')::uuid
        OR buddy_user_id = NULLIF(current_setting('app.user_id', true), '')::uuid
      )
      """)
    end

    for table <- ~w(buddy_settings support_requests wellness_summary_grants) do
      execute("""
      CREATE POLICY #{table}_owner_policy ON #{table}
      USING (user_id = NULLIF(current_setting('app.user_id', true), '')::uuid)
      WITH CHECK (user_id = NULLIF(current_setting('app.user_id', true), '')::uuid)
      """)
    end

    # A buddy reads a request delivered to them, once the undo window closed
    # and unless it was taken back (the deliveries' own policy applies
    # inside EXISTS).
    execute("""
    CREATE POLICY support_requests_buddy_read_policy ON support_requests
    FOR SELECT
    USING (
      delivered_at IS NOT NULL AND undone_at IS NULL
      AND EXISTS (
        SELECT 1 FROM support_request_deliveries d
        WHERE d.request_id = support_requests.id
          AND d.buddy_user_id = NULLIF(current_setting('app.user_id', true), '')::uuid
      )
    )
    """)

    for table <-
          ~w(buddy_links buddy_settings support_requests support_request_deliveries support_replies wellness_summary_grants) do
      execute("ALTER TABLE #{table} ENABLE ROW LEVEL SECURITY")
      execute("ALTER TABLE #{table} FORCE ROW LEVEL SECURITY")
    end
  end

  # The notification type constraint is rebuilt by several milestones; read
  # its current list instead of restating it, so order never matters.
  defp add_notification_types(types), do: rewrite_notification_types(&Enum.uniq(&1 ++ types))
  defp remove_notification_types(types), do: rewrite_notification_types(&(&1 -- types))

  defp rewrite_notification_types(change) do
    flush()

    %{rows: [[definition]]} =
      repo().query!("""
      SELECT pg_get_constraintdef(oid) FROM pg_constraint
      WHERE conname = 'notifications_type_check' AND conrelid = 'notifications'::regclass
      """)

    current = ~r/'([a-z0-9_]+)'/ |> Regex.scan(definition) |> Enum.map(&List.last/1)

    execute("ALTER TABLE notifications DROP CONSTRAINT notifications_type_check")

    execute(
      "ALTER TABLE notifications ADD CONSTRAINT notifications_type_check CHECK (type IN (#{in_list(change.(current))}))"
    )
  end

  defp in_list(types), do: Enum.map_join(types, ", ", &"'#{&1}'")
end
