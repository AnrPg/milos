defmodule Palee.Repo.Migrations.CommunityGroupEvents do
  use Ecto.Migration

  # ADR-153 §13 (P2-M5): events of a member group.
  #
  # - community_events.channel_id: the member group (a community_channels row
  #   of kind 'member_group') an event belongs to; null for club events.
  #   Group events are free and for the group's members only: no price, not
  #   open to non-members, no guest passes.
  # - From a personal session, a group event reads only for the group's
  #   members and the box's staff (plus anyone with a row on it).

  @me "NULLIF(current_setting('app.user_id', true), '')::uuid"

  def up do
    alter table(:community_events) do
      add :channel_id, :binary_id
    end

    execute("""
    ALTER TABLE community_events
    ADD CONSTRAINT community_events_channel_id_fkey
    FOREIGN KEY (channel_id, organization_id)
    REFERENCES community_channels (id, organization_id) ON DELETE CASCADE
    """)

    create constraint(:community_events, :community_events_group_check,
             check:
               "channel_id IS NULL OR (price_cents = 0 AND NOT open_to_non_members AND NOT guest_pass_allowed)"
           )

    create index(:community_events, [:channel_id, :starts_at], where: "channel_id IS NOT NULL")

    # The member groups a person belongs to, at any box.
    execute("""
    CREATE OR REPLACE FUNCTION palee_acting_user_group_ids()
    RETURNS SETOF uuid
    LANGUAGE sql
    STABLE
    SECURITY DEFINER
    SET search_path = public, pg_temp
    AS $$
      SELECT m.channel_id FROM public.community_channel_memberships m
      WHERE m.user_id = #{@me} AND m.source IN ('opt_in', 'invited', 'auto')
    $$
    """)

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
  end

  def down do
    execute("DROP POLICY community_events_member_read_policy ON community_events")

    execute("""
    CREATE POLICY community_events_member_read_policy ON community_events
    FOR SELECT
    USING (palee_acting_user_belongs_to(organization_id))
    """)

    execute("DROP FUNCTION IF EXISTS palee_acting_user_group_ids()")
    drop constraint(:community_events, :community_events_group_check)
    execute("ALTER TABLE community_events DROP CONSTRAINT community_events_channel_id_fkey")
    drop index(:community_events, [:channel_id, :starts_at])

    alter table(:community_events) do
      remove :channel_id
    end
  end
end
