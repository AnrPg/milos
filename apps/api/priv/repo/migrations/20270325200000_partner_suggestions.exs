defmodule Palee.Repo.Migrations.PartnerSuggestions do
  @moduledoc """
  ADR-280 §4: «Κλείστε μαζί» suggestions for a public Partners match.

  * `partner_suggestion_feedback`: a person's «Δεν ταιριάζει» on one
    suggestion of one match (`suggestion_key` is `kind:id`), one answer per
    person, match and key. Personal rows: the person reads and writes their
    own, vendors read them (only counts are ever shown).
  * `partner_suggestion_events`: anonymous daily counters (`shown`,
    `proposed`, `booked_together`, `feedback`), no person ids. Written only
    through `palee_partner_suggestion_count(event)`; vendors read them.
  * Definer functions, each answering only for an active match that includes
    the session user (`app.user_id`):
    - `palee_partner_suggestion_pair(match)`: both people's Partners level and
      times and their main neighbourhood's centroid (never a finer place);
    - `palee_partner_suggestion_blocked(match, ids)`: which of `ids` either
      person blocked or was blocked by;
    - `palee_partner_shared_organizations(a, b)`: live boxes where both hold
      an active (non-guest) membership.

  `partner_matches` comes from `20270325100000` (pair `user_a_id <
  user_b_id`, `status`). Every function pins only `search_path`.
  """

  use Ecto.Migration

  @acting_user "NULLIF(current_setting('app.user_id', true), '')::uuid"

  # The active match `p_match_id` when the session user is one of its two people.
  @own_match """
  FROM public.partner_matches m
  WHERE m.id = p_match_id
    AND m.status = 'active'
    AND #{@acting_user} IN (m.user_a_id, m.user_b_id)
  """

  def up do
    create table(:partner_suggestion_feedback, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :match_id, references(:partner_matches, type: :binary_id, on_delete: :delete_all),
        null: false

      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :suggestion_key, :text, null: false
      add :reason, :text, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:partner_suggestion_feedback, [:user_id, :match_id, :suggestion_key],
             name: :partner_suggestion_feedback_one_per_key_index
           )

    create index(:partner_suggestion_feedback, [:match_id])
    create index(:partner_suggestion_feedback, [:inserted_at])

    create constraint(:partner_suggestion_feedback, :partner_suggestion_feedback_reason_check,
             check: "reason IN ('not_near', 'bad_time', 'wrong_level', 'other')"
           )

    create constraint(:partner_suggestion_feedback, :partner_suggestion_feedback_key_check,
             check: "char_length(suggestion_key) BETWEEN 3 AND 120"
           )

    execute("""
    CREATE POLICY partner_suggestion_feedback_read_policy ON partner_suggestion_feedback
      FOR SELECT
      USING (
        #{@acting_user} IS NULL
        OR palee_acting_user_is_vendor()
        OR user_id = #{@acting_user}
      )
    """)

    execute("""
    CREATE POLICY partner_suggestion_feedback_write_policy ON partner_suggestion_feedback
      FOR ALL
      USING (#{@acting_user} IS NULL OR user_id = #{@acting_user})
      WITH CHECK (#{@acting_user} IS NULL OR user_id = #{@acting_user})
    """)

    execute("ALTER TABLE partner_suggestion_feedback ENABLE ROW LEVEL SECURITY")
    execute("ALTER TABLE partner_suggestion_feedback FORCE ROW LEVEL SECURITY")

    create table(:partner_suggestion_events, primary_key: false) do
      add :day, :date, primary_key: true
      add :event, :text, primary_key: true
      add :count, :bigint, null: false, default: 0
    end

    create constraint(:partner_suggestion_events, :partner_suggestion_events_event_check,
             check: "event IN ('shown', 'proposed', 'booked_together', 'feedback')"
           )

    create constraint(:partner_suggestion_events, :partner_suggestion_events_count_check,
             check: "count >= 0"
           )

    # Vendors and system sessions read; nobody writes but the function below.
    execute("""
    CREATE POLICY partner_suggestion_events_read_policy ON partner_suggestion_events
      FOR SELECT
      USING (#{@acting_user} IS NULL OR palee_acting_user_is_vendor())
    """)

    execute("ALTER TABLE partner_suggestion_events ENABLE ROW LEVEL SECURITY")
    execute("ALTER TABLE partner_suggestion_events FORCE ROW LEVEL SECURITY")

    execute("""
    CREATE FUNCTION palee_partner_suggestion_count(p_event text)
    RETURNS void
    LANGUAGE plpgsql
    VOLATILE
    SECURITY DEFINER
    SET search_path = public, pg_temp
    AS $$
    BEGIN
      IF p_event IS NULL
         OR p_event NOT IN ('shown', 'proposed', 'booked_together', 'feedback') THEN
        RAISE EXCEPTION 'unknown partner suggestion event %', p_event
          USING ERRCODE = 'invalid_parameter_value';
      END IF;

      INSERT INTO public.partner_suggestion_events AS e (day, event, count)
      VALUES ((now() AT TIME ZONE 'UTC')::date, p_event, 1)
      ON CONFLICT (day, event) DO UPDATE SET count = e.count + 1;
    END
    $$
    """)

    execute("""
    CREATE FUNCTION palee_partner_suggestion_pair(p_match_id uuid)
    RETURNS TABLE (user_id uuid, level text, times text[], latitude double precision,
                   longitude double precision)
    LANGUAGE sql
    STABLE
    SECURITY DEFINER
    SET search_path = public, pg_temp
    AS $$
      SELECT people.id, p.level::text, p.times::text[], n.latitude, n.longitude
      FROM public.partner_matches m
      CROSS JOIN LATERAL (VALUES (m.user_a_id), (m.user_b_id)) AS people(id)
      LEFT JOIN public.partner_profiles p ON p.user_id = people.id
      LEFT JOIN public.user_home_areas h ON h.user_id = people.id AND h.position = 0
      LEFT JOIN public.places_neighbourhoods n ON n.id = h.neighbourhood_id
      WHERE m.id = p_match_id
        AND m.status = 'active'
        AND #{@acting_user} IN (m.user_a_id, m.user_b_id)
    $$
    """)

    execute("""
    CREATE FUNCTION palee_partner_suggestion_blocked(p_match_id uuid, p_ids uuid[])
    RETURNS SETOF uuid
    LANGUAGE sql
    STABLE
    SECURITY DEFINER
    SET search_path = public, pg_temp
    AS $$
      SELECT DISTINCT x.id
      FROM unnest(p_ids) AS x(id)
      WHERE EXISTS (
        SELECT 1
        #{@own_match}
          AND EXISTS (
            SELECT 1 FROM public.community_user_blocks b
            WHERE (b.user_id IN (m.user_a_id, m.user_b_id) AND b.blocked_user_id = x.id)
               OR (b.blocked_user_id IN (m.user_a_id, m.user_b_id) AND b.user_id = x.id)
          )
      )
    $$
    """)

    execute("""
    CREATE OR REPLACE FUNCTION palee_partner_shared_organizations(p_a uuid, p_b uuid)
    RETURNS SETOF uuid
    LANGUAGE sql
    STABLE
    SECURITY DEFINER
    SET search_path = public, pg_temp
    AS $$
      SELECT o.id
      FROM public.organizations o
      WHERE o.status = 'active'
        AND o.activation = 'active'
        AND o.provider_kind = 'gym'
        AND #{@acting_user} IN (p_a, p_b)
        AND EXISTS (
          SELECT 1 FROM public.partner_matches m
          WHERE m.status = 'active'
            AND m.user_a_id = LEAST(p_a, p_b)
            AND m.user_b_id = GREATEST(p_a, p_b)
        )
        AND EXISTS (
          SELECT 1 FROM public.organization_memberships om
          WHERE om.organization_id = o.id AND om.user_id = p_a AND om.status = 'active'
            AND NOT (om.roles <@ ARRAY['guest']::varchar[])
        )
        AND EXISTS (
          SELECT 1 FROM public.organization_memberships om
          WHERE om.organization_id = o.id AND om.user_id = p_b AND om.status = 'active'
            AND NOT (om.roles <@ ARRAY['guest']::varchar[])
        )
    $$
    """)
  end

  def down do
    execute("DROP FUNCTION IF EXISTS palee_partner_shared_organizations(uuid, uuid)")
    execute("DROP FUNCTION IF EXISTS palee_partner_suggestion_blocked(uuid, uuid[])")
    execute("DROP FUNCTION IF EXISTS palee_partner_suggestion_pair(uuid)")
    execute("DROP FUNCTION IF EXISTS palee_partner_suggestion_count(text)")
    drop table(:partner_suggestion_events)
    drop table(:partner_suggestion_feedback)
  end
end
