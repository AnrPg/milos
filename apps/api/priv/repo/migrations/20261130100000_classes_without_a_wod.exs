defmodule Palee.Repo.Migrations.ClassesWithoutAWod do
  @moduledoc """
  ADR-176: classes may be created before their WOD. `scheduled_classes`
  already allows a null `master_workout_id`; this adds the
  `class_workout_missing` staff alert and a partial index for the sweep
  that finds upcoming classes still without a WOD.
  """

  use Ecto.Migration

  @types ~w(class_workout_missing)

  def up do
    create index(:scheduled_classes, [:organization_id, :scheduled_at],
             where: "master_workout_id IS NULL",
             name: :scheduled_classes_missing_workout_index
           )

    add_notification_types(@types)
  end

  def down do
    execute("DELETE FROM notifications WHERE type IN (#{in_list(@types)})")
    remove_notification_types(@types)

    drop index(:scheduled_classes, [:organization_id, :scheduled_at],
           name: :scheduled_classes_missing_workout_index
         )
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
