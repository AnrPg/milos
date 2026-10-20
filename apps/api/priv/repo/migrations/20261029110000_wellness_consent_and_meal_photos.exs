defmodule MilosTraining.Repo.Migrations.WellnessConsentAndMealPhotos do
  @moduledoc """
  ADR-159 §7, §9.

  - Wellness data is health data: a coach reads an entry or craving only
    while the member's `health_data` consent (ADR-158's
    `user_health_consents`) is active, besides the rung reaching them.
    Withdrawing the consent hides everything from coaches at once.
  - Meal photos: purpose `meal_photo` (the member's private storage, server
    processed like body photos), attached to their entry
    (`attached_type = 'wellness_entry'`); the daily sweep releases a photo
    whose entry was deleted.
  - Two gentle nudges, found by definer lookups that answer ids only (each
    person is then handled in their own session): «Πώς πήγε;» once for a
    craving left ongoing, and the opt-in afternoon water reminder when the
    day is under half the goal (board 14, Q2 and Q6).
  """

  @notification_types ~w(craving_follow_up water_reminder)

  use Ecto.Migration

  def up do
    execute("""
    CREATE FUNCTION milos_health_data_consented(member_id uuid)
    RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp
    AS $$
      SELECT EXISTS (
        SELECT 1 FROM public.user_health_consents c
        WHERE c.user_id = member_id AND c.scope = 'health_data' AND c.withdrawn_at IS NULL
      )
    $$
    """)

    coach_policies(true)

    rewrite_check(
      "media_account_objects",
      "media_account_objects_purpose_check",
      "purpose",
      &Enum.uniq(&1 ++ ["meal_photo"])
    )

    rewrite_attached(&Enum.uniq(&1 ++ ["wellness_entry"]))
    dangling_media(true)

    alter table(:wellness_preferences) do
      add :water_reminder, :boolean, null: false, default: false
      add :water_reminded_on, :date
      add :item_order, {:array, :text}, null: false, default: []
    end

    execute("""
    ALTER TABLE wellness_preferences ADD CONSTRAINT wellness_preferences_item_order_check
      CHECK (item_order <@ ARRAY['water', 'sleep', 'meals', 'plan', 'mood']::text[])
    """)

    nudge_functions()

    rewrite_check(
      "notifications",
      "notifications_type_check",
      "type",
      &Enum.uniq(&1 ++ @notification_types)
    )
  end

  def down do
    execute("DELETE FROM notifications WHERE type IN (#{in_list(@notification_types)})")

    rewrite_check(
      "notifications",
      "notifications_type_check",
      "type",
      &(&1 -- @notification_types)
    )

    execute("DROP FUNCTION IF EXISTS milos_craving_follow_ups_due(timestamp, integer)")
    execute("DROP FUNCTION IF EXISTS milos_water_reminders_due(timestamp, integer)")

    alter table(:wellness_preferences) do
      remove :water_reminder
      remove :water_reminded_on
      remove :item_order
    end

    execute("DELETE FROM media_account_objects WHERE purpose = 'meal_photo'")
    dangling_media(false)
    rewrite_attached(&(&1 -- ["wellness_entry"]))

    rewrite_check(
      "media_account_objects",
      "media_account_objects_purpose_check",
      "purpose",
      &(&1 -- ["meal_photo"])
    )

    coach_policies(false)
    execute("DROP FUNCTION IF EXISTS milos_health_data_consented(uuid)")
  end

  defp coach_policies(consent?) do
    for table <- ~w(wellness_entries craving_entries) do
      execute("DROP POLICY IF EXISTS #{table}_coach_read_policy ON #{table}")

      execute("""
      CREATE POLICY #{table}_coach_read_policy ON #{table}
      FOR SELECT
      USING (
        deleted_at IS NULL
        AND milos_entry_visible_to_acting_coach(user_id, organization_id, journal_visibility)
        #{if consent?, do: "AND milos_health_data_consented(user_id)", else: ""}
      )
      """)
    end
  end

  # The attached check is `(both null) OR (type IN (...) AND id not null)`.
  defp rewrite_attached(change) do
    types = current_values("media_account_objects_attached_check") |> change.()

    execute(
      "ALTER TABLE media_account_objects DROP CONSTRAINT media_account_objects_attached_check"
    )

    execute("""
    ALTER TABLE media_account_objects ADD CONSTRAINT media_account_objects_attached_check CHECK (
      (attached_type IS NULL AND attached_id IS NULL) OR
      (attached_type IN (#{in_list(types)}) AND attached_id IS NOT NULL)
    )
    """)
  end

  # Several milestones rebuild these constraints; read the current list
  # instead of restating it, so their order never matters.
  defp rewrite_check(table, name, column, change) do
    values = current_values(name) |> change.()
    execute("ALTER TABLE #{table} DROP CONSTRAINT #{name}")

    execute(
      "ALTER TABLE #{table} ADD CONSTRAINT #{name} CHECK (#{column} IN (#{in_list(values)}))"
    )
  end

  defp current_values(name) do
    flush()

    %{rows: [[definition]]} =
      repo().query!("SELECT pg_get_constraintdef(oid) FROM pg_constraint WHERE conname = $1", [
        name
      ])

    definition = definition |> String.split("::text[]") |> List.first()

    ~r/'([a-z0-9_]+)'/ |> Regex.scan(definition) |> Enum.map(&List.last/1)
  end

  # ADR-157's sweep: uploads attached to something that is gone. Restated
  # with every consumer known when this runs (posts, body snapshots, meals).
  defp dangling_media(with_meals?) do
    meals =
      if with_meals?,
        do: """
          WHEN 'wellness_entry' THEN EXISTS (
            SELECT 1 FROM wellness_entries e
            WHERE e.id = m.attached_id AND e.deleted_at IS NULL)
        """,
        else: ""

    execute("""
    CREATE OR REPLACE FUNCTION milos_dangling_post_media(cutoff timestamp, max_rows integer)
    RETURNS TABLE (user_id uuid, media_id uuid)
    LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp
    AS $$
      SELECT m.user_id, m.id
      FROM media_account_objects m
      WHERE m.attached_id IS NOT NULL AND m.attached_at < cutoff
        AND NOT CASE m.attached_type
          WHEN 'community_post' THEN EXISTS (
            SELECT 1 FROM community_posts p
            WHERE p.id = m.attached_id AND p.deleted_at IS NULL)
          WHEN 'profile_post' THEN EXISTS (
            SELECT 1 FROM community_profile_posts p
            WHERE p.id = m.attached_id AND p.deleted_at IS NULL)
          WHEN 'body_snapshot' THEN EXISTS (
            SELECT 1 FROM body_snapshots s WHERE s.id = m.attached_id)
          #{meals}
          ELSE true
        END
      ORDER BY m.attached_at
      LIMIT max_rows
    $$
    """)
  end

  defp nudge_functions do
    execute("""
    CREATE FUNCTION milos_craving_follow_ups_due(p_now timestamp, p_lim integer)
    RETURNS TABLE (user_id uuid, craving_id uuid)
    LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp
    AS $$
      SELECT c.user_id, c.id
      FROM public.craving_entries c
      WHERE c.follow_up_at IS NOT NULL AND c.follow_up_at <= p_now
        AND c.followed_up_at IS NULL AND c.deleted_at IS NULL
      ORDER BY c.follow_up_at
      LIMIT p_lim
    $$
    """)

    # The member's zone is the zone of their latest entry. Due from 15:00 to
    # 21:00 local, once a local day, while that day is under half the goal.
    execute("""
    CREATE FUNCTION milos_water_reminders_due(p_now timestamp, p_lim integer)
    RETURNS TABLE (user_id uuid, local_day date)
    LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp
    AS $$
      SELECT p.user_id, (p_now AT TIME ZONE 'UTC' AT TIME ZONE z.tz)::date
      FROM public.wellness_preferences p
      CROSS JOIN LATERAL (
        SELECT COALESCE((
          SELECT e.occurred_tz FROM public.wellness_entries e
          WHERE e.user_id = p.user_id AND e.deleted_at IS NULL
          ORDER BY e.occurred_at DESC LIMIT 1
        ), 'UTC') AS tz
      ) z
      WHERE p.water_reminder
        AND extract(hour FROM (p_now AT TIME ZONE 'UTC' AT TIME ZONE z.tz)) BETWEEN 15 AND 20
        AND p.water_reminded_on IS DISTINCT FROM (p_now AT TIME ZONE 'UTC' AT TIME ZONE z.tz)::date
        AND COALESCE((
          SELECT sum((e.value->>'ml')::integer) FROM public.wellness_entries e
          WHERE e.user_id = p.user_id AND e.kind = 'water' AND e.deleted_at IS NULL
            AND e.occurred_on = (p_now AT TIME ZONE 'UTC' AT TIME ZONE z.tz)::date
        ), 0) * 2 < p.water_goal_ml
      ORDER BY p.water_reminded_on NULLS FIRST, p.user_id
      LIMIT p_lim
    $$
    """)
  end

  defp in_list(values), do: Enum.map_join(values, ", ", &"'#{&1}'")
end
