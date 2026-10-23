defmodule Palee.Repo.Migrations.DemoPeopleMarker do
  @moduledoc """
  ADR-184 follow-up «Mock people stay private».

  - `users.demo_organization_id`: the demo business a mock person belongs to,
    set once by the members seeder and never changed (a trigger refuses it),
    so a real person can never become a mock one or the reverse. Existing
    mock people are backfilled from `demo_records`.
  - `palee_demo_user_visible(user, viewer)`: true for every real person, and
    for a mock person only when the viewer is that person or active staff of
    its demo business.
  - The person-discovery definers apply it: `palee_buddy_candidates` and the
    people half of `palee_around_match_posts` (Γύρω μου has no staff view,
    so mock people never show there).
  - `palee_notification_suppressed` also reads the marker.
  """

  use Ecto.Migration

  @staff_roles "ARRAY['owner', 'admin', 'coach', 'front_desk', 'accountant', 'janitor']::varchar[]"

  def up do
    # No foreign key on purpose: `users` outlives tenant data (the clean
    # slate purge truncates organizations CASCADE and keeps users), and a
    # deleted business's people are deleted with it by `DeleteOrganization`.
    # A mark whose business is gone still hides the person: nobody is its
    # staff any more.
    alter table(:users) do
      add :demo_organization_id, :binary_id
    end

    create index(:users, [:demo_organization_id], where: "demo_organization_id IS NOT NULL")

    # demo_records forces RLS; the backfill reads every business's rows, in
    # this migration's transaction only.
    execute("ALTER TABLE demo_records NO FORCE ROW LEVEL SECURITY")

    execute("""
    UPDATE users u
       SET demo_organization_id = d.organization_id
      FROM demo_records d
     WHERE d.source = 'users' AND d.record_id = u.id
    """)

    execute("ALTER TABLE demo_records FORCE ROW LEVEL SECURITY")

    execute("""
    CREATE OR REPLACE FUNCTION palee_guard_demo_person_marker()
    RETURNS trigger
    LANGUAGE plpgsql
    AS $$
    BEGIN
      IF NEW.demo_organization_id IS DISTINCT FROM OLD.demo_organization_id THEN
        RAISE EXCEPTION 'a mock person stays a mock person'
          USING ERRCODE = 'insufficient_privilege';
      END IF;

      RETURN NEW;
    END
    $$
    """)

    execute("""
    CREATE TRIGGER users_demo_person_marker_guard
      BEFORE UPDATE OF demo_organization_id ON users
      FOR EACH ROW EXECUTE FUNCTION palee_guard_demo_person_marker()
    """)

    execute("""
    CREATE OR REPLACE FUNCTION palee_demo_user_visible(p_user uuid, p_viewer uuid)
    RETURNS boolean
    LANGUAGE sql
    STABLE SECURITY DEFINER
    SET search_path = public, pg_temp
    AS $$
      SELECT NOT EXISTS (
        SELECT 1 FROM public.users u
        WHERE u.id = p_user AND u.demo_organization_id IS NOT NULL
          AND u.id IS DISTINCT FROM p_viewer
          AND NOT EXISTS (
            SELECT 1 FROM public.organization_memberships m
            WHERE m.organization_id = u.demo_organization_id
              AND m.user_id = p_viewer AND m.status = 'active'
              AND m.roles && #{@staff_roles}))
    $$
    """)

    execute(buddy_candidates(visible_filter()))
    execute(around_match_posts("AND u.demo_organization_id IS NULL"))
    execute(notification_suppressed(marker_suppression()))
  end

  def down do
    execute(notification_suppressed(""))
    execute(around_match_posts(""))
    execute(buddy_candidates(""))
    execute("DROP FUNCTION IF EXISTS palee_demo_user_visible(uuid, uuid)")
    execute("DROP TRIGGER IF EXISTS users_demo_person_marker_guard ON users")
    execute("DROP FUNCTION IF EXISTS palee_guard_demo_person_marker()")
    drop index(:users, [:demo_organization_id])

    alter table(:users) do
      remove :demo_organization_id
    end
  end

  defp visible_filter,
    do: "AND palee_demo_user_visible(f.user_id, (SELECT id FROM me))"

  defp marker_suppression do
    """
    OR EXISTS (
           SELECT 1 FROM public.users u
           WHERE u.id = p_user AND u.demo_organization_id IS NOT NULL)
    """
  end

  defp notification_suppressed(extra) do
    """
    CREATE OR REPLACE FUNCTION palee_notification_suppressed(p_org uuid, p_user uuid)
    RETURNS boolean
    LANGUAGE sql
    STABLE SECURITY DEFINER
    SET search_path = public, pg_temp
    AS $$
      SELECT EXISTS (
               SELECT 1 FROM public.demo_records d
               WHERE d.source = 'users' AND d.record_id = p_user)
          #{extra}
          OR EXISTS (
               SELECT 1 FROM public.organizations o
               WHERE o.id = p_org AND o.activation = 'demo'
                 AND NOT EXISTS (
                   SELECT 1 FROM public.organization_memberships m
                   WHERE m.organization_id = o.id AND m.user_id = p_user
                     AND m.status = 'active'
                     AND m.roles && #{@staff_roles}))
    $$
    """
  end

  defp buddy_candidates(extra) do
    """
    CREATE OR REPLACE FUNCTION palee_buddy_candidates(term text, lim integer)
    RETURNS TABLE(user_id uuid, relation text)
    LANGUAGE sql
    STABLE SECURITY DEFINER
    SET search_path = public, pg_temp
    AS $function$
      WITH me AS (SELECT NULLIF(current_setting('app.user_id', true), '')::uuid AS id),
      pattern AS (
        SELECT CASE WHEN term IS NULL OR length(trim(term)) < 2 THEN NULL
          ELSE replace(replace(replace(lower(trim(term)), '\\', '\\\\'), '%', '\\%'), '_', '\\_') || '%'
        END AS p
      ),
      found AS (
        SELECT r.coach_user_id AS user_id, 'coach' AS relation, 1 AS rank
        FROM coaching_relationships r
        WHERE r.client_user_id = (SELECT id FROM me) AND r.ended_at IS NULL
        UNION ALL
        SELECT CASE WHEN f.user_id = (SELECT id FROM me) THEN f.target_id ELSE f.user_id END,
               'follow', 2
        FROM community_follows f
        WHERE f.target_type = 'user' AND f.status = 'active'
          AND (f.user_id = (SELECT id FROM me) OR f.target_id = (SELECT id FROM me))
        UNION ALL
        SELECT b.user_id, 'club', 3
        FROM organization_memberships a
        JOIN organization_memberships b ON b.organization_id = a.organization_id
        WHERE (SELECT p FROM pattern) IS NOT NULL
          AND a.user_id = (SELECT id FROM me) AND a.status = 'active' AND b.status = 'active'
        UNION ALL
        SELECT b.user_id, 'club', 3
        FROM community_club_memberships a
        JOIN community_club_memberships b ON b.club_id = a.club_id
        JOIN community_clubs c ON c.id = a.club_id
        WHERE (SELECT p FROM pattern) IS NOT NULL
          AND a.user_id = (SELECT id FROM me) AND a.status = 'active' AND b.status = 'active'
          AND c.archived_at IS NULL
      ),
      ranked AS (
        SELECT DISTINCT ON (f.user_id) f.user_id, f.relation, f.rank
        FROM found f
        JOIN users u ON u.id = f.user_id
        LEFT JOIN community_social_settings s ON s.user_id = f.user_id
        WHERE f.user_id <> (SELECT id FROM me)
          AND (f.relation <> 'club' OR NOT COALESCE(s.hide_from_members, false))
          AND ((SELECT p FROM pattern) IS NULL
            OR lower(u.nickname) LIKE (SELECT p FROM pattern)
            OR lower(COALESCE(u.display_nickname, '')) LIKE (SELECT p FROM pattern))
          #{extra}
        ORDER BY f.user_id, f.rank
      )
      SELECT ranked.user_id, ranked.relation FROM ranked
      ORDER BY ranked.rank, ranked.user_id
      LIMIT LEAST(GREATEST(lim, 1), 50)
    $function$
    """
  end

  defp around_match_posts(extra) do
    """
    CREATE OR REPLACE FUNCTION palee_around_match_posts(p_origin geography, p_radius_m double precision, p_bbox geography, p_since timestamp with time zone, p_viewer_id uuid, p_disciplines text[], p_audiences text[], p_languages text[], p_amenities text[], p_created_after timestamp with time zone)
    RETURNS TABLE(id uuid, source text, organization_id uuid, author_id uuid, latitude double precision, longitude double precision, distance_m double precision, created_at timestamp with time zone, title text)
    LANGUAGE sql
    STABLE PARALLEL SAFE
    AS $function$
      SELECT p.id, 'club'::text, p.organization_id, p.author_id, h.latitude, h.longitude,
             h.distance_m, p.inserted_at, COALESCE(NULLIF(btrim(s.brand_name), ''), o.name)::text
      FROM public.palee_around_host_places(p_origin, p_radius_m, p_bbox) h
      JOIN public.organizations o ON o.id = h.organization_id
      JOIN public.organization_public_profiles pr
        ON pr.organization_id = h.organization_id AND pr.published_at IS NOT NULL
      LEFT JOIN public.organization_settings s ON s.organization_id = h.organization_id
      JOIN public.community_posts p
        ON p.organization_id = h.organization_id AND p.audience = 'public'
       AND p.deleted_at IS NULL AND p.hidden_at IS NULL
      WHERE p.inserted_at >= p_since
        AND (p_created_after IS NULL OR p.inserted_at > p_created_after)
        AND palee_around_tags_match(pr.published_snapshot, p_disciplines, p_audiences, p_languages, p_amenities)
        AND (p_viewer_id IS NULL OR NOT EXISTS (
               SELECT 1 FROM public.community_reports r
               WHERE r.target_type = 'post' AND r.target_id = p.id AND r.reporter_id = p_viewer_id))
      UNION ALL
      SELECT pp.id, 'profile'::text, NULL::uuid, pp.user_id, n.latitude, n.longitude,
             ST_Distance(palee_geo_point(n.latitude, n.longitude), p_origin), pp.inserted_at,
             u.nickname::text
      FROM public.places_neighbourhoods n
      JOIN public.user_home_areas a ON a.neighbourhood_id = n.id AND a.position = 0
      JOIN public.community_social_settings ss ON ss.user_id = a.user_id AND ss.visible_around
      JOIN public.users u ON u.id = a.user_id #{extra}
      JOIN public.community_profile_posts pp
        ON pp.user_id = a.user_id AND pp.audience = 'public' AND pp.deleted_at IS NULL
      WHERE palee_geo_point(n.latitude, n.longitude) && p_bbox
        AND ST_DWithin(palee_geo_point(n.latitude, n.longitude), p_origin, p_radius_m)
        AND pp.inserted_at >= p_since
        AND (p_created_after IS NULL OR pp.inserted_at > p_created_after)
        AND p_disciplines IS NULL AND p_audiences IS NULL AND p_languages IS NULL AND p_amenities IS NULL
    $function$
    """
  end
end
