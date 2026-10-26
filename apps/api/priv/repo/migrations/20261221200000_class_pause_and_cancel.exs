defmodule Palee.Repo.Migrations.ClassPauseAndCancel do
  @moduledoc """
  ADR-200 §2: a class can be paused (no new bookings, existing ones stay) or
  cancelled (shown as cancelled, every booking released, members told). Both
  can be undone while the class is upcoming. Adds the `class_cancelled`
  notification type.
  """

  use Ecto.Migration

  @notification_types ~w(class_cancelled)

  def up do
    alter table(:scheduled_classes) do
      add :paused_at, :utc_datetime_usec
      add :cancelled_at, :utc_datetime_usec
      add :cancel_reason, :string, size: 280
    end

    add_notification_types(@notification_types)
  end

  def down do
    execute("DELETE FROM notifications WHERE type IN (#{in_list(@notification_types)})")
    remove_notification_types(@notification_types)

    alter table(:scheduled_classes) do
      remove :paused_at
      remove :cancelled_at
      remove :cancel_reason
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
