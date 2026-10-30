defmodule Palee.Repo.Migrations.PublicPartners do
  @moduledoc """
  ADR-280 (deck side): Partners stops being per club. One account-level
  profile per person, one public deck, one active match per pair.

  Drops the ADR-169 tenant tables (`partner_messages`, `partner_matches`,
  `partner_swipes`, `partner_profiles`, with their tenant policies and
  triggers), `community_settings.partners_enabled`, and the `partner` target
  type of `community_reports` (deleting such reports). Production holds no
  real Partners data.

  Creates personal (non-tenant) tables. Row security uses `app.user_id`
  (the acting person) and `palee_acting_user_is_vendor()` for the Palee
  team, as `business_requests` (ADR-184) does; a session without an acting
  person (jobs, account deletion) is the system's. Every row of a person
  goes with the account (`on_delete: :delete_all`).

  - `partner_profiles`: one per person; `active`, `adult_confirmed_at`
    (required), `show_box` (default true), level, times, goals,
    disciplines, `about`, gender and preference, `paused_at` (Ρυθμίσεις).
    Live profiles are readable by any signed-in person (the deck).
  - `partner_swipes`: one per pair and direction of looking, like | pass.
  - `partner_matches`: pair `user_a_id < user_b_id`, at most one active.
  - `partner_messages`: text, or a plan with a jsonb snapshot.
  - `partner_reports`: a person reports another; the Palee team decides.

  `palee_partner_people_within(uuid[], double precision)` is redefined: the
  people among the ids with a live Partners profile whose main
  neighbourhood centroid is within the radius of the session user's (a
  Partners profile is the consent; Γύρω μου visibility no longer is).
  Notification types `partner_match`, `partner_message` are kept.
  Functions pin only `search_path`.
  """

  use Ecto.Migration

  @me "NULLIF(current_setting('app.user_id', true), '')::uuid"
  @system "NULLIF(current_setting('app.user_id', true), '') IS NULL"

  def up do
    drop_club_partners()
    profiles()
    swipes()
    matches()
    messages()
    reports()
    people_within(:live_profile)
  end

  def down do
    people_within(:visible_around)

    for table <-
          ~w(partner_reports partner_messages partner_matches partner_swipes partner_profiles) do
      execute("DROP TABLE IF EXISTS #{table} CASCADE")
    end

    # The ADR-169 tables are not restored: their data was dropped. Roll back
    # further (20261116100000) to recreate them.
    alter table(:community_settings) do
      add :partners_enabled, :boolean, null: false, default: true
    end

    execute("ALTER TABLE community_reports DROP CONSTRAINT community_reports_target_type_check")

    create constraint(:community_reports, :community_reports_target_type_check,
             check: "target_type IN ('post', 'comment', 'channel', 'partner')"
           )
  end

  # -- the club side goes ----------------------------------------------------

  defp drop_club_partners do
    for table <- ~w(partner_messages partner_matches partner_swipes partner_profiles) do
      execute("DROP TABLE IF EXISTS #{table} CASCADE")
    end

    alter table(:community_settings) do
      remove :partners_enabled
    end

    execute("DELETE FROM community_reports WHERE target_type = 'partner'")
    execute("ALTER TABLE community_reports DROP CONSTRAINT community_reports_target_type_check")

    create constraint(:community_reports, :community_reports_target_type_check,
             check: "target_type IN ('post', 'comment', 'channel')"
           )
  end

  # -- profiles ----------------------------------------------------------------

  defp profiles do
    create table(:partner_profiles, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :active, :boolean, null: false, default: true
      add :adult_confirmed_at, :utc_datetime_usec, null: false
      add :show_box, :boolean, null: false, default: true
      add :level, :text, null: false
      add :times, {:array, :text}, null: false, default: []
      add :goals, {:array, :text}, null: false, default: []
      add :disciplines, {:array, :text}, null: false, default: []
      add :about, :text
      add :gender, :text
      add :gender_preference, :text, null: false, default: "any"
      add :paused_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:partner_profiles, [:user_id])

    create index(:partner_profiles, [:user_id],
             where: "active AND paused_at IS NULL",
             name: :partner_profiles_live_index
           )

    create constraint(:partner_profiles, :partner_profiles_level_check,
             check: "level IN ('beginner', 'intermediate', 'advanced')"
           )

    create constraint(:partner_profiles, :partner_profiles_times_check,
             check:
               "times <@ ARRAY['early', 'midday', 'afternoon', 'evening', 'weekend']::text[] " <>
                 "AND cardinality(times) BETWEEN 1 AND 5"
           )

    create constraint(:partner_profiles, :partner_profiles_goals_check,
             check:
               "goals <@ ARRAY['strength', 'conditioning', 'weight_loss', 'skills', " <>
                 "'competition', 'consistency']::text[] AND cardinality(goals) BETWEEN 1 AND 3"
           )

    create constraint(:partner_profiles, :partner_profiles_disciplines_check,
             check: "cardinality(disciplines) <= 5"
           )

    create constraint(:partner_profiles, :partner_profiles_about_check,
             check: "about IS NULL OR char_length(about) BETWEEN 1 AND 140"
           )

    create constraint(:partner_profiles, :partner_profiles_gender_check,
             check: "gender IS NULL OR gender IN ('woman', 'man', 'other')"
           )

    create constraint(:partner_profiles, :partner_profiles_gender_preference_check,
             check: "gender_preference IN ('any', 'women', 'men')"
           )

    owner = "(#{@system} OR user_id = #{@me})"
    staff = "(#{owner} OR palee_acting_user_is_vendor())"

    policies(:partner_profiles, [
      # The deck: a live profile is readable by any signed-in person; the
      # application shows only verified people.
      {"read", "SELECT", "USING (#{staff} OR (active AND paused_at IS NULL))"},
      {"insert", "INSERT", "WITH CHECK (#{owner})"},
      {"update", "UPDATE", "USING (#{staff}) WITH CHECK (#{staff})"},
      {"delete", "DELETE", "USING (#{staff})"}
    ])
  end

  # -- swipes ------------------------------------------------------------------

  defp swipes do
    create table(:partner_swipes, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :swiper_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :target_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :direction, :text, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:partner_swipes, [:swiper_id, :target_id])
    create index(:partner_swipes, [:target_id, :direction])
    create index(:partner_swipes, [:swiper_id, :updated_at])

    create constraint(:partner_swipes, :partner_swipes_direction_check,
             check: "direction IN ('like', 'pass')"
           )

    create constraint(:partner_swipes, :partner_swipes_pair_check,
             check: "swiper_id <> target_id"
           )

    swiper = "(#{@system} OR swiper_id = #{@me})"

    policies(:partner_swipes, [
      # The target reads it only so a crossing like makes the match; the API
      # never says who liked whom before it is mutual.
      {"read", "SELECT", "USING (#{swiper} OR target_id = #{@me})"},
      {"insert", "INSERT", "WITH CHECK (#{swiper})"},
      {"update", "UPDATE", "USING (#{swiper}) WITH CHECK (#{swiper})"},
      {"delete", "DELETE", "USING (#{swiper})"}
    ])
  end

  # -- matches -----------------------------------------------------------------

  defp matches do
    create table(:partner_matches, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_a_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :user_b_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :status, :text, null: false, default: "active"
      add :matched_at, :utc_datetime_usec, null: false
      add :ended_at, :utc_datetime_usec
      add :ended_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :end_reason, :text
      add :a_read_at, :utc_datetime_usec
      add :b_read_at, :utc_datetime_usec
      add :last_message_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:partner_matches, [:user_a_id, :user_b_id],
             where: "status = 'active'",
             name: :partner_matches_active_pair_index
           )

    create index(:partner_matches, [:user_a_id, :status])
    create index(:partner_matches, [:user_b_id, :status])

    create constraint(:partner_matches, :partner_matches_pair_check,
             check: "user_a_id < user_b_id"
           )

    create constraint(:partner_matches, :partner_matches_status_check,
             check: "status IN ('active', 'ended')"
           )

    create constraint(:partner_matches, :partner_matches_end_check,
             check:
               "(status = 'active' AND ended_at IS NULL AND end_reason IS NULL) OR " <>
                 "(status = 'ended' AND ended_at IS NOT NULL AND end_reason IN " <>
                 "('unmatched', 'blocked', 'reported', 'suspended'))"
           )

    party = "(#{@system} OR user_a_id = #{@me} OR user_b_id = #{@me})"
    staff = "(#{party} OR palee_acting_user_is_vendor())"

    policies(:partner_matches, [
      {"read", "SELECT", "USING (#{staff})"},
      {"insert", "INSERT", "WITH CHECK (#{party} AND status = 'active')"},
      {"update", "UPDATE", "USING (#{staff}) WITH CHECK (#{staff})"},
      {"delete", "DELETE", "USING (#{@system})"}
    ])
  end

  # -- messages ----------------------------------------------------------------

  defp messages do
    create table(:partner_messages, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :match_id, references(:partner_matches, type: :binary_id, on_delete: :delete_all),
        null: false

      add :author_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :kind, :text, null: false, default: "text"
      add :body, :text
      add :plan, :jsonb

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:partner_messages, [:match_id, :inserted_at, :id])
    create index(:partner_messages, [:author_id])

    create constraint(:partner_messages, :partner_messages_kind_check,
             check:
               "(kind = 'text' AND body IS NOT NULL AND plan IS NULL) OR " <>
                 "(kind = 'plan' AND plan IS NOT NULL AND jsonb_typeof(plan) = 'object' " <>
                 "AND plan->>'kind' IN ('class', 'event', 'trial'))"
           )

    create constraint(:partner_messages, :partner_messages_body_check,
             check: "body IS NULL OR char_length(body) BETWEEN 1 AND 2000"
           )

    in_match = fn condition ->
      "EXISTS (SELECT 1 FROM partner_matches m WHERE m.id = partner_messages.match_id " <>
        "AND (m.user_a_id = #{@me} OR m.user_b_id = #{@me})#{condition})"
    end

    policies(:partner_messages, [
      {"read", "SELECT", "USING (#{@system} OR #{in_match.("")})"},
      {"insert", "INSERT",
       "WITH CHECK (#{@system} OR (author_id = #{@me} AND #{in_match.(" AND m.status = 'active'")}))"},
      {"delete", "DELETE", "USING (#{@system})"}
    ])
  end

  # -- reports -----------------------------------------------------------------

  defp reports do
    create table(:partner_reports, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :reporter_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      add :target_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :reason, :text, null: false
      add :note, :text
      add :status, :text, null: false, default: "open"
      add :decided_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :decided_at, :utc_datetime_usec
      add :decision_note, :text

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:partner_reports, [:reporter_id, :target_id],
             where: "status = 'open'",
             name: :partner_reports_open_pair_index
           )

    create index(:partner_reports, [:status, :inserted_at])
    create index(:partner_reports, [:target_id, :status])

    create constraint(:partner_reports, :partner_reports_pair_check,
             check: "reporter_id <> target_id"
           )

    create constraint(:partner_reports, :partner_reports_reason_check,
             check: "reason IN ('unsafe', 'fake', 'minor', 'harassment', 'other')"
           )

    create constraint(:partner_reports, :partner_reports_status_check,
             check:
               "(status = 'open' AND decided_at IS NULL) OR " <>
                 "(status IN ('actioned', 'dismissed') AND decided_at IS NOT NULL)"
           )

    create constraint(:partner_reports, :partner_reports_text_check,
             check:
               "(note IS NULL OR char_length(note) BETWEEN 1 AND 500) AND " <>
                 "(decision_note IS NULL OR char_length(decision_note) BETWEEN 1 AND 500)"
           )

    staff = "(#{@system} OR palee_acting_user_is_vendor())"

    policies(:partner_reports, [
      {"read", "SELECT", "USING (#{staff} OR reporter_id = #{@me})"},
      {"insert", "INSERT",
       "WITH CHECK (#{staff} OR (reporter_id = #{@me} AND status = 'open' " <>
         "AND decided_by_id IS NULL AND decided_at IS NULL))"},
      {"update", "UPDATE", "USING (#{staff}) WITH CHECK (#{staff})"},
      {"delete", "DELETE", "USING (#{staff})"}
    ])
  end

  # -- distance (ADR-197 kept, ADR-280 consent) ------------------------------

  defp people_within(consent) do
    counted =
      case consent do
        :live_profile ->
          "JOIN public.partner_profiles pp ON pp.user_id = a.user_id " <>
            "AND pp.active AND pp.paused_at IS NULL"

        :visible_around ->
          "JOIN public.community_social_settings ss ON ss.user_id = a.user_id " <>
            "AND ss.visible_around"
      end

    execute("DROP FUNCTION IF EXISTS palee_partner_people_within(uuid[], double precision)")

    execute("""
    CREATE FUNCTION palee_partner_people_within(p_people uuid[], p_radius_m double precision)
    RETURNS SETOF uuid
    LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp
    AS $$
      SELECT a.user_id
      FROM public.user_home_areas me
      JOIN public.places_neighbourhoods mine ON mine.id = me.neighbourhood_id
      JOIN public.user_home_areas a ON a.position = 0 AND a.user_id = ANY (p_people)
      JOIN public.places_neighbourhoods n ON n.id = a.neighbourhood_id
      #{counted}
      WHERE me.user_id = #{@me}
        AND me.position = 0
        AND a.user_id <> me.user_id
        AND ST_DWithin(
              palee_geo_point(n.latitude, n.longitude),
              palee_geo_point(mine.latitude, mine.longitude),
              p_radius_m)
    $$
    """)
  end

  defp policies(table, rules) do
    for {name, command, clause} <- rules do
      execute("CREATE POLICY #{table}_#{name}_policy ON #{table} FOR #{command} #{clause}")
    end

    execute("ALTER TABLE #{table} ENABLE ROW LEVEL SECURITY")
    execute("ALTER TABLE #{table} FORCE ROW LEVEL SECURITY")
  end
end
