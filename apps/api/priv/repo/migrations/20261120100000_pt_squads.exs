defmodule MilosTraining.Repo.Migrations.PtSquads do
  @moduledoc """
  PT squads (ADR-168): a coach's small invite-only channel with their own
  clients, inside the gym's club.

  - A squad is a channel of kind 'pt_squad' (same table as member groups and
    the season channel). Its coach is `created_by_id`.
  - An invitation is a channel membership with source 'pending_invite'; it is
    not a member until the client accepts ('invited'). Declining, leaving,
    being removed or the coaching ending set 'dismissed'.
  - One name per coach among their live squads.
  - Notification type `community_squad_invited`, added to whatever the
    constraint holds now so parallel migrations keep their types.
  """

  use Ecto.Migration

  @channel_kinds_before ~w(announcements wod challenges class_slot season custom member_group general)
  @channel_kinds @channel_kinds_before ++ ["pt_squad"]
  @sources_before ~w(opt_in suggested invited auto dismissed requested)
  @sources @sources_before ++ ["pending_invite"]
  @notification_types ~w(community_squad_invited)

  def up do
    replace_check(:community_channels, :community_channels_kind_check, "kind", @channel_kinds)

    replace_check(
      :community_channel_memberships,
      :community_channel_memberships_source_check,
      "source",
      @sources
    )

    execute("""
    CREATE UNIQUE INDEX community_channels_squad_name_index
    ON community_channels (club_id, created_by_id, lower(name))
    WHERE kind = 'pt_squad' AND archived_at IS NULL
    """)

    create index(:community_channels, [:club_id, :created_by_id],
             where: "kind = 'pt_squad'",
             name: :community_channels_squads_by_coach_index
           )

    add_notification_types(@notification_types)
  end

  def down do
    execute("DELETE FROM notifications WHERE type IN (#{in_list(@notification_types)})")
    remove_notification_types(@notification_types)

    execute("DROP INDEX IF EXISTS community_channels_squads_by_coach_index")
    execute("DROP INDEX IF EXISTS community_channels_squad_name_index")

    execute("DELETE FROM community_channel_memberships WHERE source = 'pending_invite'")

    replace_check(
      :community_channel_memberships,
      :community_channel_memberships_source_check,
      "source",
      @sources_before
    )

    execute("DELETE FROM community_channels WHERE kind = 'pt_squad'")

    replace_check(
      :community_channels,
      :community_channels_kind_check,
      "kind",
      @channel_kinds_before
    )
  end

  defp replace_check(table, name, column, values) do
    drop constraint(table, name)
    create constraint(table, name, check: "#{column} IN (#{in_list(values)})")
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
