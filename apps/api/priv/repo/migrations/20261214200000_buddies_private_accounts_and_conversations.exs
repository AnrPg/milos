defmodule Palee.Repo.Migrations.BuddiesPrivateAccountsAndConversations do
  @moduledoc """
  ADR-193: Buddies (mutual follows), private accounts, person-to-person
  conversations and people search.

  - `community_social_settings.private_account` (default true: nobody's
    exposure changes) and `searchable` (default true). A missing row reads
    as private and searchable.
  - `palee_user_is_public(uuid)`: whether a person turned private off. The
    follower's insert policy on `community_follows` now allows an `active`
    follow of a person only when that person is public.
  - `person_conversations`: one per pair (`user_a_id < user_b_id`), each
    side with its own folder (`inbox | requests | declined`) and read mark.
    Only the two people read or write it. A guard trigger keeps the pair
    and the starter fixed, lets each side move only its own read mark and
    never lets one side decline for the other.
  - `person_messages`: immutable; written by one of the pair, as
    themselves, while neither blocked the other.
  - `palee_follow_groups(uuid)`: a person's Buddies, people who follow
    them only and people they follow only (numbers anyone may see).
  - `palee_person_relations(uuid[])`: for the session user and each other
    person, whether they share an active gym or open club, follow each
    other, or share a home neighbourhood.
  - `palee_people_search(text, text, integer)`: ranked people search
    (club, buddy, follow, nearby, public); private or unsearchable people
    only through relations the viewer already has.
  - notification types `person_message`, `message_request`, `new_follower`.
  """

  use Ecto.Migration

  @notification_types ~w(person_message message_request new_follower)
  @me "NULLIF(current_setting('app.user_id', true), '')::uuid"

  def up do
    alter table(:community_social_settings) do
      add :private_account, :boolean, null: false, default: true
      add :searchable, :boolean, null: false, default: true
    end

    execute("""
    CREATE OR REPLACE FUNCTION palee_user_is_public(person uuid)
    RETURNS boolean
    LANGUAGE sql
    STABLE SECURITY DEFINER
    SET search_path = public, pg_temp
    AS $$
      SELECT COALESCE(
        (SELECT NOT s.private_account FROM public.community_social_settings s
         WHERE s.user_id = person),
        false)
    $$
    """)

    follow_insert_policy(
      "(target_type <> 'user' OR status = 'requested' OR " <>
        "(status = 'active' AND palee_user_is_public(target_id)))"
    )

    # The three groups of a person's follows that never overlap (ADR-193
    # §1): Buddies (both ways), people who follow them only, and people they
    # follow only. Numbers anyone may see, like follower counts.
    execute("""
    CREATE OR REPLACE FUNCTION palee_follow_groups(account uuid)
    RETURNS TABLE (buddies bigint, followers_only bigint, following_only bigint)
    LANGUAGE sql
    STABLE SECURITY DEFINER
    SET search_path = public, pg_temp
    AS $$
      WITH outgoing AS (
        SELECT f.target_id AS id FROM public.community_follows f
        WHERE f.user_id = account AND f.target_type = 'user' AND f.status = 'active'
      ), incoming AS (
        SELECT f.user_id AS id FROM public.community_follows f
        WHERE f.target_id = account AND f.target_type = 'user' AND f.status = 'active'
      )
      SELECT
        (SELECT count(*) FROM outgoing o JOIN incoming i USING (id)),
        (SELECT count(*) FROM incoming i WHERE i.id NOT IN (SELECT id FROM outgoing)),
        (SELECT count(*) FROM outgoing o WHERE o.id NOT IN (SELECT id FROM incoming))
    $$
    """)

    conversations()
    messages()
    relations_function()
    search_function()
    add_notification_types(@notification_types)
  end

  def down do
    execute("DELETE FROM notifications WHERE type IN (#{in_list(@notification_types)})")
    remove_notification_types(@notification_types)

    execute("DROP FUNCTION IF EXISTS palee_people_search(text, text, integer)")
    execute("DROP FUNCTION IF EXISTS palee_person_relations(uuid[])")
    drop table(:person_messages)
    drop table(:person_conversations)
    execute("DROP FUNCTION IF EXISTS palee_person_conversations_guard()")

    execute("DROP FUNCTION IF EXISTS palee_follow_groups(uuid)")
    follow_insert_policy("(target_type <> 'user' OR status = 'requested')")
    execute("DROP FUNCTION IF EXISTS palee_user_is_public(uuid)")

    alter table(:community_social_settings) do
      remove :searchable
      remove :private_account
    end
  end

  defp follow_insert_policy(status_rule) do
    execute("DROP POLICY IF EXISTS community_follows_owner_insert_policy ON community_follows")

    execute("""
    CREATE POLICY community_follows_owner_insert_policy ON community_follows
    FOR INSERT WITH CHECK (user_id = #{@me} AND #{status_rule})
    """)
  end

  defp conversations do
    create table(:person_conversations, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_a_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :user_b_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      add :started_by_id, references(:users, type: :binary_id, on_delete: :delete_all),
        null: false

      add :a_folder, :string, null: false
      add :b_folder, :string, null: false
      add :a_read_at, :utc_datetime_usec
      add :b_read_at, :utc_datetime_usec
      add :last_message_at, :utc_datetime_usec
      add :last_author_id, references(:users, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:person_conversations, [:user_a_id, :user_b_id])
    create index(:person_conversations, [:user_a_id, :last_message_at])
    create index(:person_conversations, [:user_b_id, :last_message_at])

    create constraint(:person_conversations, :person_conversations_pair_check,
             check: "user_a_id < user_b_id"
           )

    create constraint(:person_conversations, :person_conversations_starter_check,
             check: "started_by_id IN (user_a_id, user_b_id)"
           )

    for side <- ~w(a b) do
      create constraint(:person_conversations, :"person_conversations_#{side}_folder_check",
               check: "#{side}_folder IN ('inbox', 'requests', 'declined')"
             )
    end

    party = "(user_a_id = #{@me} OR user_b_id = #{@me})"

    for {name, command, clause} <- [
          {"read", "SELECT", "USING (#{party})"},
          {"insert", "INSERT", "WITH CHECK (#{party} AND started_by_id = #{@me})"},
          {"update", "UPDATE", "USING (#{party}) WITH CHECK (#{party})"}
        ] do
      execute(
        "CREATE POLICY person_conversations_party_#{name}_policy ON person_conversations FOR #{command} #{clause}"
      )
    end

    # Rows may be changed only by one of the pair (the policy), and then only
    # as ADR-193 §3 allows: the pair and the starter never change, a read
    # mark only by its own side, and nobody declines for the other side.
    execute("""
    CREATE OR REPLACE FUNCTION palee_person_conversations_guard()
    RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
    AS $$
    DECLARE
      me uuid := #{@me};
    BEGIN
      IF NEW.user_a_id <> OLD.user_a_id OR NEW.user_b_id <> OLD.user_b_id
         OR NEW.started_by_id <> OLD.started_by_id THEN
        RAISE EXCEPTION 'person conversation pair is immutable';
      END IF;

      IF me IS NULL THEN
        RETURN NEW;
      END IF;

      IF NEW.a_read_at IS DISTINCT FROM OLD.a_read_at AND me <> OLD.user_a_id THEN
        RAISE EXCEPTION 'only its own side moves a read mark';
      END IF;

      IF NEW.b_read_at IS DISTINCT FROM OLD.b_read_at AND me <> OLD.user_b_id THEN
        RAISE EXCEPTION 'only its own side moves a read mark';
      END IF;

      IF NEW.a_folder IS DISTINCT FROM OLD.a_folder AND me <> OLD.user_a_id
         AND NEW.a_folder = 'declined' THEN
        RAISE EXCEPTION 'only its own side declines';
      END IF;

      IF NEW.b_folder IS DISTINCT FROM OLD.b_folder AND me <> OLD.user_b_id
         AND NEW.b_folder = 'declined' THEN
        RAISE EXCEPTION 'only its own side declines';
      END IF;

      RETURN NEW;
    END
    $$
    """)

    execute("""
    CREATE TRIGGER person_conversations_guard
    BEFORE UPDATE ON person_conversations
    FOR EACH ROW EXECUTE FUNCTION palee_person_conversations_guard()
    """)

    secure(:person_conversations)
  end

  defp messages do
    create table(:person_messages, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :conversation_id,
          references(:person_conversations, type: :binary_id, on_delete: :delete_all),
          null: false

      add :user_a_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :user_b_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :author_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :body, :text, null: false
      add :client_operation_id, :binary_id

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:person_messages, [:conversation_id, :inserted_at, :id])

    create unique_index(:person_messages, [:author_id, :client_operation_id],
             where: "client_operation_id IS NOT NULL",
             name: :person_messages_client_operation_index
           )

    create constraint(:person_messages, :person_messages_body_check,
             check: "char_length(body) BETWEEN 1 AND 2000"
           )

    create constraint(:person_messages, :person_messages_author_check,
             check: "author_id IN (user_a_id, user_b_id)"
           )

    execute("""
    CREATE POLICY person_messages_party_read_policy ON person_messages
    FOR SELECT USING (user_a_id = #{@me} OR user_b_id = #{@me})
    """)

    # Written by one of the pair, as themselves, into their own conversation
    # (whose policy applies inside EXISTS), while neither blocked the other.
    execute("""
    CREATE POLICY person_messages_author_insert_policy ON person_messages
    FOR INSERT WITH CHECK (
      author_id = #{@me}
      AND EXISTS (
        SELECT 1 FROM person_conversations c
        WHERE c.id = conversation_id
          AND c.user_a_id = person_messages.user_a_id
          AND c.user_b_id = person_messages.user_b_id)
      AND NOT EXISTS (
        SELECT 1 FROM palee_blocked_user_ids() b(id)
        WHERE b.id IN (person_messages.user_a_id, person_messages.user_b_id))
    )
    """)

    secure(:person_messages)
  end

  # Facts about the session user and each other person, without opening
  # anyone's memberships, follows or home areas to row reads.
  defp relations_function do
    execute("""
    CREATE OR REPLACE FUNCTION palee_person_relations(others uuid[])
    RETURNS TABLE (user_id uuid, shares_club boolean, i_follow boolean,
                   follows_me boolean, nearby boolean)
    LANGUAGE sql
    STABLE SECURITY DEFINER
    SET search_path = public, pg_temp
    AS $$
      WITH me AS (SELECT #{@me} AS id)
      SELECT o.id,
        EXISTS (
          SELECT 1 FROM organization_memberships a
          JOIN organization_memberships b ON b.organization_id = a.organization_id
          WHERE a.user_id = (SELECT id FROM me) AND b.user_id = o.id
            AND a.status = 'active' AND b.status = 'active'
        ) OR EXISTS (
          SELECT 1 FROM community_club_memberships a
          JOIN community_club_memberships b ON b.club_id = a.club_id
          JOIN community_clubs c ON c.id = a.club_id
          WHERE a.user_id = (SELECT id FROM me) AND b.user_id = o.id
            AND a.status = 'active' AND b.status = 'active'
            AND c.kind = 'open' AND c.archived_at IS NULL
        ),
        EXISTS (
          SELECT 1 FROM community_follows f
          WHERE f.user_id = (SELECT id FROM me) AND f.target_type = 'user'
            AND f.target_id = o.id AND f.status = 'active'
        ),
        EXISTS (
          SELECT 1 FROM community_follows f
          WHERE f.user_id = o.id AND f.target_type = 'user'
            AND f.target_id = (SELECT id FROM me) AND f.status = 'active'
        ),
        EXISTS (
          SELECT 1 FROM user_home_areas a
          JOIN user_home_areas b ON b.neighbourhood_id = a.neighbourhood_id
          WHERE a.user_id = (SELECT id FROM me) AND b.user_id = o.id
        )
      FROM unnest(others) AS o(id)
      WHERE (SELECT id FROM me) IS NOT NULL AND o.id <> (SELECT id FROM me)
    $$
    """)
  end

  defp search_function do
    execute("""
    CREATE OR REPLACE FUNCTION palee_people_search(handle_term text, name_term text, lim integer)
    RETURNS TABLE (user_id uuid, relation text)
    LANGUAGE sql
    STABLE SECURITY DEFINER
    SET search_path = public, pg_temp
    AS $function$
      WITH me AS (SELECT #{@me} AS id),
      terms AS (
        SELECT
          CASE WHEN length(COALESCE(handle_term, '')) < 1 THEN NULL
            ELSE replace(replace(replace(handle_term, '\\', '\\\\'), '%', '\\%'), '_', '\\_') || '%'
          END AS handle_p,
          CASE WHEN length(COALESCE(name_term, '')) < 2 THEN NULL
            ELSE '%' || replace(replace(replace(name_term, '\\', '\\\\'), '%', '\\%'), '_', '\\_') || '%'
          END AS name_p
      ),
      candidates AS (
        SELECT u.id, u.nickname
        FROM users u
        WHERE (SELECT id FROM me) IS NOT NULL
          AND u.id <> (SELECT id FROM me)
          AND u.demo_organization_id IS NULL
          AND ((SELECT handle_p FROM terms) IS NOT NULL OR (SELECT name_p FROM terms) IS NOT NULL)
          AND (u.nickname LIKE (SELECT handle_p FROM terms)
            OR u.search_text LIKE (SELECT name_p FROM terms))
          AND u.id NOT IN (
            SELECT b.blocked_user_id FROM community_user_blocks b WHERE b.user_id = (SELECT id FROM me)
            UNION
            SELECT b.user_id FROM community_user_blocks b WHERE b.blocked_user_id = (SELECT id FROM me))
        LIMIT 500
      ),
      facts AS (
        SELECT c.id, c.nickname,
          COALESCE(s.private_account, true) AS private,
          COALESCE(s.searchable, true) AS searchable,
          COALESCE(s.hide_from_members, false) AS hidden_member,
          r.shares_club, r.i_follow, r.follows_me, r.nearby
        FROM candidates c
        LEFT JOIN community_social_settings s ON s.user_id = c.id
        JOIN palee_person_relations(ARRAY(SELECT id FROM candidates)) r ON r.user_id = c.id
      ),
      ranked AS (
        SELECT f.id, f.nickname,
          CASE
            WHEN f.shares_club AND (NOT f.hidden_member OR f.searchable) THEN 1
            WHEN f.i_follow AND f.follows_me THEN 2
            WHEN f.i_follow OR f.follows_me THEN 3
            WHEN NOT f.private AND f.searchable AND f.nearby THEN 4
            WHEN NOT f.private AND f.searchable THEN 5
          END AS rank
        FROM facts f
      )
      SELECT ranked.id,
        CASE ranked.rank WHEN 1 THEN 'club' WHEN 2 THEN 'buddy' WHEN 3 THEN 'follow'
          WHEN 4 THEN 'nearby' ELSE 'public' END
      FROM ranked
      WHERE ranked.rank IS NOT NULL
      ORDER BY ranked.rank,
        CASE WHEN ranked.nickname = handle_term THEN 0 ELSE 1 END,
        ranked.nickname
      LIMIT LEAST(GREATEST(lim, 1), 50)
    $function$
    """)
  end

  defp secure(table) do
    execute("ALTER TABLE #{table} ENABLE ROW LEVEL SECURITY")
    execute("ALTER TABLE #{table} FORCE ROW LEVEL SECURITY")
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
