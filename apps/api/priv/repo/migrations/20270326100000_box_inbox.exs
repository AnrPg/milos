defmodule Palee.Repo.Migrations.BoxInbox do
  @moduledoc """
  ADR-282: anyone can write to a box, and the box answers from one shared
  inbox.

    * `messaging_participants.joined_as`: why someone is in a box thread
      (`member` the person it is with, `staff` the box's inbox, `coach` a
      coach the topic «Προπόνηση» or «Φέρε τον coach» brought in). Box
      access is worked out from the roles at read time; the row keeps the
      read marker. Staff rows of box threads made before this are marked
      `staff`, and the coaches the old code added to every box thread lose
      them, as coaches only join a box thread when brought in.
    * Messages a person writes to the box may carry a topic too, and
      `training` (Προπόνηση) joins the topics.
    * `messaging_box_blocks`: people a box will no longer hear from.
    * Notification type `box_inbox_message`: someone wrote to the box.
  """

  use Ecto.Migration

  @types ~w(box_inbox_message)

  def up do
    alter table(:messaging_participants) do
      add :joined_as, :string
    end

    create constraint(:messaging_participants, :messaging_participants_joined_as_check,
             check: "joined_as IS NULL OR joined_as IN ('member', 'staff', 'coach')"
           )

    execute("""
    UPDATE messaging_participants p SET joined_as = 'member'
    FROM messaging_threads t
    WHERE t.id = p.thread_id AND t.context_type = 'box' AND p.user_id = t.context_id
    """)

    # Coaches were added to every box thread; they come in only when brought
    # in now. Owners, admins and anyone else on the box's side stay as staff.
    execute("""
    DELETE FROM messaging_participants p
    USING messaging_threads t
    WHERE t.id = p.thread_id AND t.context_type = 'box' AND p.user_id <> t.context_id
      AND NOT EXISTS (
        SELECT 1 FROM organization_memberships m
        WHERE m.organization_id = t.organization_id AND m.user_id = p.user_id
          AND m.status = 'active'
          AND m.roles && ARRAY['owner', 'admin', 'front_desk', 'accountant']::varchar[]
      )
    """)

    execute("""
    UPDATE messaging_participants p SET joined_as = 'staff'
    FROM messaging_threads t
    WHERE t.id = p.thread_id AND t.context_type = 'box' AND p.joined_as IS NULL
    """)

    drop constraint(:messaging_messages, :messaging_messages_topic_check)

    create constraint(:messaging_messages, :messaging_messages_topic_check,
             check:
               "topic IS NULL OR (message_type IN ('box_message', 'chat') AND " <>
                 "topic IN ('booking', 'payment', 'membership', 'facility', 'training'))"
           )

    create table(:messaging_box_blocks, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :blocked_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(:messaging_box_blocks, [:organization_id, :user_id])

    execute("""
    CREATE TRIGGER messaging_box_blocks_apply_tenant_context
    BEFORE INSERT OR UPDATE ON messaging_box_blocks
    FOR EACH ROW EXECUTE FUNCTION palee_apply_tenant_context()
    """)

    execute("""
    CREATE POLICY messaging_box_blocks_tenant_policy ON messaging_box_blocks
    USING (organization_id = NULLIF(current_setting('app.organization_id', true), '')::uuid)
    WITH CHECK (organization_id = NULLIF(current_setting('app.organization_id', true), '')::uuid)
    """)

    execute("ALTER TABLE messaging_box_blocks ENABLE ROW LEVEL SECURITY")
    execute("ALTER TABLE messaging_box_blocks FORCE ROW LEVEL SECURITY")

    rewrite_notification_types(&Enum.uniq(&1 ++ @types))
  end

  def down do
    execute("DELETE FROM notifications WHERE type IN ('box_inbox_message')")
    rewrite_notification_types(&(&1 -- @types))

    drop table(:messaging_box_blocks)

    execute("UPDATE messaging_messages SET topic = NULL WHERE message_type = 'chat'")
    execute("UPDATE messaging_messages SET topic = NULL WHERE topic = 'training'")
    drop constraint(:messaging_messages, :messaging_messages_topic_check)

    create constraint(:messaging_messages, :messaging_messages_topic_check,
             check:
               "topic IS NULL OR (message_type = 'box_message' AND " <>
                 "topic IN ('booking', 'payment', 'membership', 'facility'))"
           )

    drop constraint(:messaging_participants, :messaging_participants_joined_as_check)

    alter table(:messaging_participants) do
      remove :joined_as
    end
  end

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
      "ALTER TABLE notifications ADD CONSTRAINT notifications_type_check CHECK (type IN (#{Enum.map_join(change.(current), ", ", &"'#{&1}'")}))"
    )
  end
end
