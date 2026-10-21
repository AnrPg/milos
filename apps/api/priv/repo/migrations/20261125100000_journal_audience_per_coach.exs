defmodule MilosTraining.Repo.Migrations.JournalAudiencePerCoach do
  @moduledoc """
  ADR-162 (ANR, 2026-10-21): «Οι coach μου» names individual coaches, not
  whole providers. An entry's own audience and the default's exclusions get
  `coach_user_id`; the rows that named a provider become one row per coach
  it has today. A provider's coaches still always read what was recorded
  there (`milos_entry_visible_to_acting_coach`); these rows only decide who
  else reads a shared entry.

  `milos_journal_entry_shared_with_coach` replaces
  `milos_journal_entry_shared_with_org` and `milos_entry_shared_with_acting_coach`
  passes the acting coach, so every policy and the coach feed check one
  coach of one provider. `milos_my_provider_coaches()` lists the coaches of
  the caller's active providers, for the chooser.
  """

  use Ecto.Migration

  @acting_user "NULLIF(current_setting('app.user_id', true), '')::uuid"
  @acting_org "NULLIF(current_setting('app.organization_id', true), '')::uuid"

  # Active coaches of an organization, never the member themself.
  @coaches """
  SELECT m.organization_id, m.user_id AS coach_user_id
  FROM organization_memberships m
  WHERE m.status = 'active' AND 'coach' = ANY (m.roles)
  """

  def up do
    for {table, key} <- [
          {"journal_entry_audiences", "entry_kind, entry_id, organization_id"},
          {"journal_coach_audience_exclusions", "user_id, organization_id"}
        ] do
      execute("ALTER TABLE #{table} DROP CONSTRAINT #{table}_pkey")

      execute("""
      ALTER TABLE #{table}
      ADD COLUMN coach_user_id uuid REFERENCES users(id) ON DELETE CASCADE
      """)

      columns = String.replace(key, "organization_id", "c.organization_id")

      execute("""
      INSERT INTO #{table} (#{key}, #{extra_columns(table)}coach_user_id, inserted_at)
      SELECT #{prefixed(columns)}, #{extra_select(table)}c.coach_user_id, t.inserted_at
      FROM #{table} t
      JOIN (#{@coaches}) c ON c.organization_id = t.organization_id
      WHERE t.coach_user_id IS NULL AND c.coach_user_id <> t.user_id
      """)

      execute("DELETE FROM #{table} WHERE coach_user_id IS NULL")
      execute("ALTER TABLE #{table} ALTER COLUMN coach_user_id SET NOT NULL")
      execute("ALTER TABLE #{table} ADD PRIMARY KEY (#{key}, coach_user_id)")
    end

    execute("""
    CREATE FUNCTION milos_journal_entry_shared_with_coach(
      kind text, entry uuid, entry_user_id uuid, entry_org_id uuid, org uuid, coach uuid
    )
    RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp
    AS $$
      SELECT org IS NOT NULL
        AND coach IS NOT NULL
        AND org IS DISTINCT FROM entry_org_id
        AND EXISTS (
          SELECT 1 FROM public.organization_memberships m
          WHERE m.organization_id = org AND m.user_id = entry_user_id AND m.status = 'active'
        )
        AND (
          EXISTS (
            SELECT 1 FROM public.journal_entry_audiences a
            WHERE a.entry_kind = kind AND a.entry_id = entry AND a.user_id = entry_user_id
              AND a.organization_id = org AND a.coach_user_id = coach
          )
          OR (
            entry_org_id IS NULL
            AND NOT EXISTS (
              SELECT 1 FROM public.journal_entry_audiences a
              WHERE a.entry_kind = kind AND a.entry_id = entry AND a.user_id = entry_user_id
            )
            AND NOT EXISTS (
              SELECT 1 FROM public.journal_coach_audience_exclusions x
              WHERE x.user_id = entry_user_id AND x.organization_id = org
                AND x.coach_user_id = coach
            )
          )
        )
    $$
    """)

    execute("""
    CREATE OR REPLACE FUNCTION milos_entry_shared_with_acting_coach(
      kind text, entry uuid, entry_user_id uuid, entry_org_id uuid, visibility text
    )
    RETURNS boolean
    LANGUAGE sql STABLE
    AS $$
      SELECT public.milos_journal_visibility_reaches_coach(visibility)
        AND #{@acting_org} IS NOT NULL
        AND public.milos_acting_user_coaches(#{@acting_org})
        AND public.milos_journal_entry_shared_with_coach(
          kind, entry, entry_user_id, entry_org_id, #{@acting_org}, #{@acting_user}
        )
    $$
    """)

    execute("DROP FUNCTION milos_journal_entry_shared_with_org(text, uuid, uuid, uuid, uuid)")

    # The coaches of the caller's active providers (whose memberships a
    # member's session cannot read), without the caller.
    execute("""
    CREATE FUNCTION milos_my_provider_coaches()
    RETURNS TABLE (organization_id uuid, coach_user_id uuid)
    LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp
    AS $$
      SELECT c.organization_id, c.user_id
      FROM public.organization_memberships me
      JOIN public.organizations o ON o.id = me.organization_id AND o.status = 'active'
      JOIN public.organization_memberships c
        ON c.organization_id = me.organization_id
       AND c.status = 'active' AND 'coach' = ANY (c.roles)
       AND c.user_id <> me.user_id
      WHERE me.user_id = #{@acting_user} AND me.status = 'active'
    $$
    """)
  end

  def down do
    execute("DROP FUNCTION IF EXISTS milos_my_provider_coaches()")

    execute("""
    CREATE FUNCTION milos_journal_entry_shared_with_org(
      kind text, entry uuid, entry_user_id uuid, entry_org_id uuid, org uuid
    )
    RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp
    AS $$
      SELECT org IS NOT NULL
        AND org IS DISTINCT FROM entry_org_id
        AND EXISTS (
          SELECT 1 FROM public.organization_memberships m
          WHERE m.organization_id = org AND m.user_id = entry_user_id AND m.status = 'active'
        )
        AND (
          EXISTS (
            SELECT 1 FROM public.journal_entry_audiences a
            WHERE a.entry_kind = kind AND a.entry_id = entry AND a.organization_id = org
              AND a.user_id = entry_user_id
          )
          OR (
            entry_org_id IS NULL
            AND NOT EXISTS (
              SELECT 1 FROM public.journal_entry_audiences a
              WHERE a.entry_kind = kind AND a.entry_id = entry AND a.user_id = entry_user_id
            )
            AND NOT EXISTS (
              SELECT 1 FROM public.journal_coach_audience_exclusions x
              WHERE x.user_id = entry_user_id AND x.organization_id = org
            )
          )
        )
    $$
    """)

    execute("""
    CREATE OR REPLACE FUNCTION milos_entry_shared_with_acting_coach(
      kind text, entry uuid, entry_user_id uuid, entry_org_id uuid, visibility text
    )
    RETURNS boolean
    LANGUAGE sql STABLE
    AS $$
      SELECT public.milos_journal_visibility_reaches_coach(visibility)
        AND #{@acting_org} IS NOT NULL
        AND public.milos_acting_user_coaches(#{@acting_org})
        AND public.milos_journal_entry_shared_with_org(
          kind, entry, entry_user_id, entry_org_id, #{@acting_org}
        )
    $$
    """)

    execute(
      "DROP FUNCTION milos_journal_entry_shared_with_coach(text, uuid, uuid, uuid, uuid, uuid)"
    )

    for {table, key} <- [
          {"journal_entry_audiences", "entry_kind, entry_id, organization_id"},
          {"journal_coach_audience_exclusions", "user_id, organization_id"}
        ] do
      execute("ALTER TABLE #{table} DROP CONSTRAINT #{table}_pkey")

      execute("""
      DELETE FROM #{table} t USING #{table} d
      WHERE #{Enum.map_join(String.split(key, ", "), " AND ", &"t.#{&1} = d.#{&1}")}
        AND t.coach_user_id > d.coach_user_id
      """)

      execute("ALTER TABLE #{table} DROP COLUMN coach_user_id")
      execute("ALTER TABLE #{table} ADD PRIMARY KEY (#{key})")
    end
  end

  defp prefixed(columns) do
    columns
    |> String.split(", ")
    |> Enum.map_join(", ", fn
      "c." <> _ = column -> column
      column -> "t." <> column
    end)
  end

  defp extra_columns("journal_entry_audiences"), do: "user_id, "
  defp extra_columns(_table), do: ""
  defp extra_select("journal_entry_audiences"), do: "t.user_id, "
  defp extra_select(_table), do: ""
end
