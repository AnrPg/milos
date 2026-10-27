defmodule Palee.Repo.Migrations.EmailDeliverability do
  @moduledoc """
  ADR-212: what the mail provider tells Palee after a send, opt-outs and
  retention.

  - `email_messages` gains `delivered_at` and two statuses: `bounced` (the
    provider reported a hard bounce, an invalid address or a block) and
    `complained` (the reader marked it as spam).
  - `email_provider_events`: one row per provider webhook event, keyed by a
    digest of the event itself, so a webhook Brevo retries is applied once.
    Soft bounces are only recorded here.
  - `email_opt_outs`: an address that unsubscribed from one transactional
    kind (List-Unsubscribe, RFC 8058). Security and account mail ignore it.
  - Indexes for the retention sweep (90 days of messages, 7 days of spent
    link tokens).
  - Notification type `email_key_expiring` (vendors: the SMTP key expires).

  Platform tables like ADR-203's: written by the webhook, the unsubscribe
  link and the email worker with no session scope, never read by a tenant
  session, so no RLS. Neither table has an `organization_id`.
  """

  use Ecto.Migration

  @old_statuses ~w(queued sent failed suppressed deferred)
  @statuses @old_statuses ++ ~w(bounced complained)
  @notification_types ~w(email_key_expiring)

  def up do
    alter table(:email_messages) do
      add :delivered_at, :utc_datetime_usec
    end

    execute("ALTER TABLE email_messages DROP CONSTRAINT email_messages_status_check")

    execute(
      "ALTER TABLE email_messages ADD CONSTRAINT email_messages_status_check CHECK (status IN (#{in_list(@statuses)}))"
    )

    create index(:email_messages, [:inserted_at])
    create index(:email_messages, [:status], where: "status = 'deferred'")

    create table(:email_provider_events, primary_key: false) do
      add :event_digest, :binary, primary_key: true
      add :provider, :string, null: false
      add :event, :string, null: false
      add :email_message_id, references(:email_messages, type: :binary_id, on_delete: :delete_all)
      add :address_digest, :binary
      add :reason, :text
      add :occurred_at, :utc_datetime_usec
      add :inserted_at, :utc_datetime_usec, null: false, default: fragment("now()")
    end

    create index(:email_provider_events, [:email_message_id])
    create index(:email_provider_events, [:inserted_at])

    create table(:email_opt_outs, primary_key: false) do
      add :address_digest, :binary, primary_key: true
      add :kind, :string, primary_key: true
      add :inserted_at, :utc_datetime_usec, null: false, default: fragment("now()")
    end

    create index(:email_link_tokens, [:expires_at])

    add_notification_types(@notification_types)
  end

  def down do
    execute("DELETE FROM notifications WHERE type IN (#{in_list(@notification_types)})")
    remove_notification_types(@notification_types)

    drop index(:email_link_tokens, [:expires_at])
    drop table(:email_opt_outs)
    drop table(:email_provider_events)
    drop index(:email_messages, [:status], where: "status = 'deferred'")
    drop index(:email_messages, [:inserted_at])

    execute("UPDATE email_messages SET status = 'sent' WHERE status IN ('bounced', 'complained')")
    execute("ALTER TABLE email_messages DROP CONSTRAINT email_messages_status_check")

    execute(
      "ALTER TABLE email_messages ADD CONSTRAINT email_messages_status_check CHECK (status IN (#{in_list(@old_statuses)}))"
    )

    alter table(:email_messages) do
      remove :delivered_at
    end
  end

  defp add_notification_types(types), do: rewrite_notification_types(&Enum.uniq(&1 ++ types))
  defp remove_notification_types(types), do: rewrite_notification_types(&(&1 -- types))

  # The same read-modify-write of notifications_type_check as earlier
  # migrations, so types other migrations added stay.
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

  defp in_list(values), do: Enum.map_join(values, ", ", &"'#{&1}'")
end
