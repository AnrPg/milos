defmodule MilosTraining.Repo.Migrations.BuddyMessagesAndWellnessAccess do
  @moduledoc """
  ADR-160 follow-up: the buddy conversation, the coach's wellness-summary
  read log and the coach's Sunday summary push.

  - `buddy_messages`: the pair's own conversation, one thread per buddy
    link, account-scoped (it never depends on a gym the two share). Each row
    carries the link's two people (`user_id`, `buddy_user_id`) and its
    author; a body of at most 2000 characters; `read_at` once the other
    person read it. Only the two people read it; a message can be written
    only into an active link, so an ended link's thread stays readable but
    read-only; only the recipient may mark a message read, and nothing else
    of a message can change.
  - `support_replies` now point at the message they posted (`message_id`)
    and the link (`link_id`); the gym-scoped thread columns are dropped.
  - `wellness_access_log`: one row per coach read of a member's weekly
    wellness summary (who, whose, in which gym, which week, whether the
    craving moments were shown). Gym-scoped like `body_access_log`: the
    member reads their own rows; the gym's rows go with the gym.

  Definer lookups for the Sunday coach push: members with the wellness
  toggle on (ids and zones), and, for one such member, the coaches with an
  active coaching relationship in a gym where the member is active.
  """

  use Ecto.Migration

  @notification_types ~w(buddy_message coach_wellness_summary)

  def up do
    create table(:buddy_messages, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :link_id, references(:buddy_links, type: :binary_id, on_delete: :delete_all),
        null: false

      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      add :buddy_user_id, references(:users, type: :binary_id, on_delete: :delete_all),
        null: false

      add :author_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :body, :text, null: false
      add :read_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create constraint(:buddy_messages, :buddy_messages_body_check,
             check: "char_length(body) BETWEEN 1 AND 2000"
           )

    create constraint(:buddy_messages, :buddy_messages_author_check,
             check: "author_id = user_id OR author_id = buddy_user_id"
           )

    create index(:buddy_messages, [:link_id, :inserted_at, :id])

    execute("DROP POLICY IF EXISTS support_replies_party_policy ON support_replies")

    alter table(:support_replies) do
      remove :thread_id
      remove :conversation_organization_id
      add :link_id, references(:buddy_links, type: :binary_id, on_delete: :nilify_all)
      add :message_id, references(:buddy_messages, type: :binary_id, on_delete: :nilify_all)
    end

    party_policy("support_replies")

    create table(:wellness_access_log, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      add :reader_user_id, references(:users, type: :binary_id, on_delete: :delete_all),
        null: false

      add :week_start, :date, null: false
      add :shared, :boolean, null: false, default: false
      add :cravings_shown, :boolean, null: false, default: false
      add :read_at, :utc_datetime_usec, null: false

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:wellness_access_log, [:user_id, :read_at])
    create index(:wellness_access_log, [:organization_id, :read_at])

    message_policies()
    access_log_policies()
    functions()
    add_notification_types(@notification_types)
  end

  def down do
    execute("DELETE FROM notifications WHERE type IN (#{in_list(@notification_types)})")
    remove_notification_types(@notification_types)

    for function <- [
          "milos_wellness_summary_members(integer)",
          "milos_wellness_summary_coaches(uuid)"
        ] do
      execute("DROP FUNCTION IF EXISTS #{function}")
    end

    drop table(:wellness_access_log)

    execute("DROP POLICY IF EXISTS support_replies_party_policy ON support_replies")

    alter table(:support_replies) do
      remove :message_id
      remove :link_id
      add :thread_id, :binary_id
      add :conversation_organization_id, :binary_id
    end

    party_policy("support_replies")

    drop table(:buddy_messages)
    execute("DROP FUNCTION IF EXISTS milos_buddy_messages_guard()")
  end

  defp party_policy(table) do
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

  defp message_policies do
    me = "NULLIF(current_setting('app.user_id', true), '')::uuid"

    execute("""
    CREATE POLICY buddy_messages_party_read_policy ON buddy_messages
    FOR SELECT
    USING (user_id = #{me} OR buddy_user_id = #{me})
    """)

    # Written by one of the pair, as themselves, into an active link of the
    # same two people (the links' own policy applies inside EXISTS).
    execute("""
    CREATE POLICY buddy_messages_author_insert_policy ON buddy_messages
    FOR INSERT
    WITH CHECK (
      author_id = #{me}
      AND (user_id = #{me} OR buddy_user_id = #{me})
      AND EXISTS (
        SELECT 1 FROM buddy_links l
        WHERE l.id = buddy_messages.link_id AND l.status = 'active'
          AND l.user_id = buddy_messages.user_id
          AND l.buddy_user_id = buddy_messages.buddy_user_id
      )
    )
    """)

    # Only the recipient marks a message read.
    execute("""
    CREATE POLICY buddy_messages_recipient_update_policy ON buddy_messages
    FOR UPDATE
    USING ((user_id = #{me} OR buddy_user_id = #{me}) AND author_id <> #{me})
    WITH CHECK ((user_id = #{me} OR buddy_user_id = #{me}) AND author_id <> #{me})
    """)

    # A message's content, author and pair never change; only read_at.
    execute("""
    CREATE FUNCTION milos_buddy_messages_guard()
    RETURNS trigger
    LANGUAGE plpgsql
    AS $$
    BEGIN
      IF NEW.link_id IS DISTINCT FROM OLD.link_id
         OR NEW.user_id IS DISTINCT FROM OLD.user_id
         OR NEW.buddy_user_id IS DISTINCT FROM OLD.buddy_user_id
         OR NEW.author_id IS DISTINCT FROM OLD.author_id
         OR NEW.body IS DISTINCT FROM OLD.body
         OR NEW.inserted_at IS DISTINCT FROM OLD.inserted_at THEN
        RAISE EXCEPTION 'buddy messages are immutable' USING ERRCODE = 'check_violation';
      END IF;
      RETURN NEW;
    END
    $$
    """)

    execute("""
    CREATE TRIGGER buddy_messages_guard
    BEFORE UPDATE ON buddy_messages
    FOR EACH ROW EXECUTE FUNCTION milos_buddy_messages_guard()
    """)

    execute("ALTER TABLE buddy_messages ENABLE ROW LEVEL SECURITY")
    execute("ALTER TABLE buddy_messages FORCE ROW LEVEL SECURITY")
  end

  defp access_log_policies do
    execute("""
    CREATE TRIGGER wellness_access_log_apply_tenant_context
    BEFORE INSERT OR UPDATE ON wellness_access_log
    FOR EACH ROW EXECUTE FUNCTION milos_apply_tenant_context()
    """)

    execute("""
    CREATE POLICY wellness_access_log_tenant_policy ON wellness_access_log
    USING (organization_id = NULLIF(current_setting('app.organization_id', true), '')::uuid)
    WITH CHECK (organization_id = NULLIF(current_setting('app.organization_id', true), '')::uuid)
    """)

    execute("""
    CREATE POLICY wellness_access_log_owner_read_policy ON wellness_access_log
    FOR SELECT
    USING (user_id = NULLIF(current_setting('app.user_id', true), '')::uuid)
    """)

    execute("ALTER TABLE wellness_access_log ENABLE ROW LEVEL SECURITY")
    execute("ALTER TABLE wellness_access_log FORCE ROW LEVEL SECURITY")
  end

  defp functions do
    # Members whose coaches get the weekly wellness summary, with the zone
    # their week is counted in. Ids and zones only.
    execute("""
    CREATE FUNCTION milos_wellness_summary_members(lim integer)
    RETURNS TABLE (user_id uuid, tz text)
    LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp
    AS $$
      SELECT g.user_id, COALESCE(s.tz, 'Europe/Athens')
      FROM wellness_summary_grants g
      LEFT JOIN buddy_settings s ON s.user_id = g.user_id
      WHERE g.scope = 'wellness' AND g.withdrawn_at IS NULL
      ORDER BY g.user_id
      LIMIT lim
    $$
    """)

    # The coaches of one such member: an active coaching relationship in a
    # gym where the member is active. Answers nothing without the toggle.
    execute("""
    CREATE FUNCTION milos_wellness_summary_coaches(member uuid)
    RETURNS TABLE (organization_id uuid, coach_user_id uuid)
    LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp
    AS $$
      SELECT DISTINCT r.organization_id, r.coach_user_id
      FROM coaching_relationships r
      JOIN organization_memberships m
        ON m.organization_id = r.organization_id AND m.user_id = r.client_user_id
      WHERE r.client_user_id = member AND r.ended_at IS NULL AND m.status = 'active'
        AND EXISTS (
          SELECT 1 FROM wellness_summary_grants g
          WHERE g.user_id = member AND g.scope = 'wellness' AND g.withdrawn_at IS NULL
        )
      ORDER BY r.organization_id, r.coach_user_id
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

    current = ~r/'([a-z0-9_]+)'/ |> Regex.scan(definition) |> Enum.map(&List.last/1)

    execute("ALTER TABLE notifications DROP CONSTRAINT notifications_type_check")

    execute(
      "ALTER TABLE notifications ADD CONSTRAINT notifications_type_check CHECK (type IN (#{in_list(change.(current))}))"
    )
  end

  defp in_list(types), do: Enum.map_join(types, ", ", &"'#{&1}'")
end
