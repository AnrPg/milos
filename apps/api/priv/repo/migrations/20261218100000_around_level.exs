defmodule Palee.Repo.Migrations.AroundLevel do
  @moduledoc """
  Γύρω μου «Επίπεδο» (vision §7.2, ADR-197): every discovery function takes
  `p_levels text[]` right after `p_amenities`. A host matches when it runs a
  current (not archived) class type at one of the levels; NULL means any.
  A person's post has no host, so it drops out like with the tags.

  The bodies are those of `20261214100000_around_price_range` (events,
  counts, pins), `20261209100000_demo_people_marker` (posts) and
  `20261024100000_around_me` (the rest), with the level check added;
  `down` renders them again without it.
  """

  use Ecto.Migration

  @live "AND o.activation = 'active'"
  @definer "LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp"
  @tags "text[], text[], text[], text[]"

  def up do
    drop_all(false)

    execute("""
    CREATE FUNCTION palee_around_level_match(p_organization_id uuid, p_levels text[])
    RETURNS boolean
    LANGUAGE sql STABLE PARALLEL SAFE
    AS $$
      SELECT p_levels IS NULL OR EXISTS (
        SELECT 1 FROM public.class_types ct
        WHERE ct.organization_id = p_organization_id AND ct.archived_at IS NULL
          AND ct.level = ANY (p_levels))
    $$
    """)

    create_all(true)
  end

  def down do
    drop_all(true)
    execute("DROP FUNCTION IF EXISTS palee_around_level_match(uuid, text[])")
    create_all(false)
  end

  defp create_all(levels?) do
    Enum.each(
      [
        match_events(levels?),
        match_boxes(levels?),
        match_clubs(levels?),
        match_posts(levels?),
        events(levels?),
        boxes(levels?),
        clubs(levels?),
        posts(levels?),
        counts(levels?),
        pins(levels?)
      ],
      &execute/1
    )
  end

  # Wrappers first: they depend on the matchers.
  defp drop_all(levels?) do
    tags = if levels?, do: @tags <> ", text[]", else: @tags

    [
      {"palee_around_events",
       "geography, double precision, geography, timestamptz, timestamptz[], timestamptz[], integer, integer, " <>
         "#{tags}, timestamptz, timestamptz, uuid, integer"},
      {"palee_around_boxes",
       "geography, double precision, geography, boolean, uuid[], #{tags}, timestamptz, integer, " <>
         "double precision, uuid, integer"},
      {"palee_around_clubs",
       "geography, double precision, geography, #{tags}, timestamptz, double precision, uuid, integer"},
      {"palee_around_posts",
       "geography, double precision, geography, timestamptz, uuid, #{tags}, timestamptz, timestamptz, uuid, integer"},
      {"palee_around_counts",
       "geography, double precision[], double precision, geography, text[], timestamptz, timestamptz[], " <>
         "timestamptz[], integer, integer, boolean, uuid[], timestamptz, uuid, #{tags}, timestamptz"},
      {"palee_around_pins",
       "geography, double precision, geography, text[], timestamptz, timestamptz[], timestamptz[], integer, " <>
         "integer, boolean, uuid[], timestamptz, uuid, #{tags}, integer"},
      {"palee_around_match_events",
       "geography, double precision, geography, timestamptz, timestamptz[], timestamptz[], integer, integer, " <>
         "#{tags}, timestamptz"},
      {"palee_around_match_boxes",
       "geography, double precision, geography, boolean, uuid[], #{tags}, timestamptz"},
      {"palee_around_match_clubs",
       "geography, double precision, geography, #{tags}, timestamptz"},
      {"palee_around_match_posts",
       "geography, double precision, geography, timestamptz, uuid, #{tags}, timestamptz"}
    ]
    |> Enum.each(fn {name, args} -> execute("DROP FUNCTION IF EXISTS #{name}(#{args})") end)
  end

  # The tag parameters, as declared and as passed on.
  defp tag_params(true),
    do:
      "p_disciplines text[], p_audiences text[], p_languages text[], p_amenities text[], p_levels text[]"

  defp tag_params(false),
    do: "p_disciplines text[], p_audiences text[], p_languages text[], p_amenities text[]"

  defp tag_args(true), do: "p_disciplines, p_audiences, p_languages, p_amenities, p_levels"
  defp tag_args(false), do: "p_disciplines, p_audiences, p_languages, p_amenities"

  defp level_clause(true, organization),
    do: "\n        AND palee_around_level_match(#{organization}, p_levels)"

  defp level_clause(false, _organization), do: ""

  defp match_events(levels?) do
    """
    CREATE FUNCTION palee_around_match_events(p_origin geography, p_radius_m double precision, p_bbox geography, p_now_at timestamp with time zone, p_win_from timestamp with time zone[], p_win_to timestamp with time zone[], p_max_price_cents integer, p_min_price_cents integer, #{tag_params(levels?)}, p_created_after timestamp with time zone)
     RETURNS TABLE(id uuid, organization_id uuid, latitude double precision, longitude double precision, distance_m double precision, starts_at timestamp with time zone, created_at timestamp with time zone, title text)
     LANGUAGE sql
     STABLE PARALLEL SAFE
    AS $function$
      SELECT e.id, e.organization_id, placed.latitude, placed.longitude, placed.distance_m,
             e.starts_at, e.inserted_at, e.title::text
      FROM (
        SELECT pe.id, pe.latitude, pe.longitude,
               ST_Distance(palee_geo_point(pe.latitude, pe.longitude), p_origin) AS distance_m
        FROM public.community_events pe
        WHERE pe.open_to_non_members AND pe.cancelled_at IS NULL AND pe.latitude IS NOT NULL
          AND palee_geo_point(pe.latitude, pe.longitude) && p_bbox
          AND ST_DWithin(palee_geo_point(pe.latitude, pe.longitude), p_origin, p_radius_m)
          AND pe.starts_at >= p_now_at
        UNION ALL
        SELECT le.id, l.latitude, l.longitude,
               ST_Distance(palee_geo_point(l.latitude, l.longitude), p_origin)
        FROM public.facility_locations l
        JOIN public.community_events le
          ON le.location_id = l.id AND le.organization_id = l.organization_id
        WHERE l.latitude IS NOT NULL AND l.archived_at IS NULL
          AND palee_geo_point(l.latitude, l.longitude) && p_bbox
          AND ST_DWithin(palee_geo_point(l.latitude, l.longitude), p_origin, p_radius_m)
          AND le.open_to_non_members AND le.cancelled_at IS NULL AND le.location_id IS NOT NULL
          AND le.latitude IS NULL AND le.starts_at >= p_now_at
        UNION ALL
        SELECT he.id, h.latitude, h.longitude, h.distance_m
        FROM public.palee_around_host_places(p_origin, p_radius_m, p_bbox) h
        JOIN public.community_events he ON he.organization_id = h.organization_id
        WHERE he.open_to_non_members AND he.cancelled_at IS NULL
          AND he.latitude IS NULL AND he.location_id IS NULL AND he.starts_at >= p_now_at
      ) placed
      JOIN public.community_events e ON e.id = placed.id
      JOIN public.organizations o ON o.id = e.organization_id AND o.status = 'active' #{@live}
      LEFT JOIN public.organization_public_profiles pr
        ON pr.organization_id = e.organization_id AND pr.published_at IS NOT NULL
      WHERE (p_win_from IS NULL OR EXISTS (
               SELECT 1 FROM unnest(p_win_from, p_win_to) AS w(f, t)
               WHERE e.starts_at >= w.f AND e.starts_at < w.t))
        AND (p_max_price_cents IS NULL OR e.price_cents <= p_max_price_cents)
        AND (p_min_price_cents IS NULL OR e.price_cents >= p_min_price_cents)
        AND (p_created_after IS NULL OR e.inserted_at > p_created_after)
        AND palee_around_tags_match(pr.published_snapshot, p_disciplines, p_audiences, p_languages, p_amenities)#{level_clause(levels?, "e.organization_id")}
    $function$
    """
  end

  defp match_boxes(levels?) do
    """
    CREATE FUNCTION palee_around_match_boxes(
      p_origin geography, p_radius_m double precision, p_bbox geography,
      p_trial_only boolean, p_exclude_ids uuid[],
      #{tag_params(levels?)},
      p_created_after timestamptz
    )
    RETURNS TABLE (
      organization_id uuid, location_id uuid, latitude double precision,
      longitude double precision, distance_m double precision, neighbourhood text, city text,
      takes_trials boolean, snapshot jsonb, published_at timestamptz, slug text, title text,
      logo_url text, primary_color text
    )
    LANGUAGE sql STABLE PARALLEL SAFE
    AS $$
      SELECT h.organization_id, h.location_id, h.latitude, h.longitude, h.distance_m,
             h.neighbourhood, h.city, COALESCE(t.enabled, false), pr.published_snapshot,
             pr.published_at, o.slug::text, COALESCE(NULLIF(btrim(s.brand_name), ''), o.name)::text,
             s.brand_logo_url::text, s.brand_primary_color::text
      FROM public.palee_around_host_places(p_origin, p_radius_m, p_bbox) h
      JOIN public.organizations o ON o.id = h.organization_id
      JOIN public.organization_public_profiles pr
        ON pr.organization_id = h.organization_id AND pr.published_at IS NOT NULL
      LEFT JOIN public.organization_settings s ON s.organization_id = h.organization_id
      LEFT JOIN public.scheduling_trial_policies t ON t.organization_id = h.organization_id
      WHERE (NOT p_trial_only OR COALESCE(t.enabled, false))
        AND (p_exclude_ids IS NULL OR NOT (h.organization_id = ANY (p_exclude_ids)))
        AND (p_created_after IS NULL OR pr.published_at > p_created_after)
        AND palee_around_tags_match(pr.published_snapshot, p_disciplines, p_audiences, p_languages, p_amenities)#{level_clause(levels?, "h.organization_id")}
    $$
    """
  end

  defp match_clubs(levels?) do
    """
    CREATE FUNCTION palee_around_match_clubs(
      p_origin geography, p_radius_m double precision, p_bbox geography,
      #{tag_params(levels?)},
      p_created_after timestamptz
    )
    RETURNS TABLE (
      id uuid, organization_id uuid, latitude double precision, longitude double precision,
      distance_m double precision, created_at timestamptz, title text
    )
    LANGUAGE sql STABLE PARALLEL SAFE
    AS $$
      SELECT c.id, c.organization_id, h.latitude, h.longitude, h.distance_m, c.inserted_at,
             c.name::text
      FROM public.palee_around_host_places(p_origin, p_radius_m, p_bbox) h
      JOIN public.community_clubs c
        ON c.organization_id = h.organization_id AND c.kind = 'open' AND c.archived_at IS NULL
      LEFT JOIN public.organization_public_profiles pr
        ON pr.organization_id = h.organization_id AND pr.published_at IS NOT NULL
      WHERE c.join_policy IN ('open', 'approval')
        AND (p_created_after IS NULL OR c.inserted_at > p_created_after)
        AND palee_around_tags_match(pr.published_snapshot, p_disciplines, p_audiences, p_languages, p_amenities)#{level_clause(levels?, "h.organization_id")}
    $$
    """
  end

  defp match_posts(levels?) do
    no_level = if levels?, do: " AND p_levels IS NULL", else: ""

    """
    CREATE FUNCTION palee_around_match_posts(
      p_origin geography, p_radius_m double precision, p_bbox geography, p_since timestamptz,
      p_viewer_id uuid, #{tag_params(levels?)},
      p_created_after timestamptz
    )
    RETURNS TABLE (
      id uuid, source text, organization_id uuid, author_id uuid, latitude double precision,
      longitude double precision, distance_m double precision, created_at timestamptz,
      title text
    )
    LANGUAGE sql STABLE PARALLEL SAFE
    AS $$
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
        AND palee_around_tags_match(pr.published_snapshot, p_disciplines, p_audiences, p_languages, p_amenities)#{level_clause(levels?, "h.organization_id")}
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
      JOIN public.users u ON u.id = a.user_id AND u.demo_organization_id IS NULL
      JOIN public.community_profile_posts pp
        ON pp.user_id = a.user_id AND pp.audience = 'public' AND pp.deleted_at IS NULL
      WHERE palee_geo_point(n.latitude, n.longitude) && p_bbox
        AND ST_DWithin(palee_geo_point(n.latitude, n.longitude), p_origin, p_radius_m)
        AND pp.inserted_at >= p_since
        AND (p_created_after IS NULL OR pp.inserted_at > p_created_after)
        AND p_disciplines IS NULL AND p_audiences IS NULL AND p_languages IS NULL AND p_amenities IS NULL#{no_level}
    $$
    """
  end

  defp events(levels?) do
    """
    CREATE FUNCTION palee_around_events(
      p_origin geography, p_radius_m double precision, p_bbox geography, p_now_at timestamptz,
      p_win_from timestamptz[], p_win_to timestamptz[], p_max_price_cents integer, p_min_price_cents integer,
      #{tag_params(levels?)},
      p_created_after timestamptz, p_after_starts_at timestamptz, p_after_id uuid, p_lim integer
    )
    RETURNS TABLE (
      id uuid, organization_id uuid, latitude double precision, longitude double precision,
      distance_m double precision, starts_at timestamptz, total bigint
    )
    #{@definer}
    AS $$
      SELECT m.id, m.organization_id, m.latitude, m.longitude, m.distance_m, m.starts_at, m.total
      FROM (
        SELECT x.*, count(*) OVER () AS total
        FROM palee_around_match_events(p_origin, p_radius_m, p_bbox, p_now_at, p_win_from, p_win_to,
               p_max_price_cents, p_min_price_cents, #{tag_args(levels?)}, p_created_after) x
      ) m
      WHERE p_after_id IS NULL OR (m.starts_at, m.id) > (p_after_starts_at, p_after_id)
      ORDER BY m.starts_at, m.id
      LIMIT p_lim
    $$
    """
  end

  defp boxes(levels?) do
    """
    CREATE FUNCTION palee_around_boxes(
      p_origin geography, p_radius_m double precision, p_bbox geography,
      p_trial_only boolean, p_exclude_ids uuid[],
      #{tag_params(levels?)},
      p_created_after timestamptz, p_after_rank integer, p_after_distance double precision,
      p_after_id uuid, p_lim integer
    )
    RETURNS TABLE (
      organization_id uuid, location_id uuid, latitude double precision,
      longitude double precision, distance_m double precision, neighbourhood text, city text,
      takes_trials boolean, snapshot jsonb, slug text, title text, logo_url text,
      primary_color text, rank integer, total bigint
    )
    #{@definer}
    AS $$
      SELECT m.organization_id, m.location_id, m.latitude, m.longitude, m.distance_m,
             m.neighbourhood, m.city, m.takes_trials, m.snapshot, m.slug, m.title, m.logo_url,
             m.primary_color, m.rank, m.total
      FROM (
        SELECT x.*, CASE WHEN x.takes_trials THEN 0 ELSE 1 END AS rank,
               count(*) OVER () AS total
        FROM palee_around_match_boxes(p_origin, p_radius_m, p_bbox, p_trial_only, p_exclude_ids,
               #{tag_args(levels?)}, p_created_after) x
      ) m
      WHERE p_after_id IS NULL
         OR (m.rank, m.distance_m, m.organization_id) > (p_after_rank, p_after_distance, p_after_id)
      ORDER BY m.rank, m.distance_m, m.organization_id
      LIMIT p_lim
    $$
    """
  end

  defp clubs(levels?) do
    """
    CREATE FUNCTION palee_around_clubs(
      p_origin geography, p_radius_m double precision, p_bbox geography,
      #{tag_params(levels?)},
      p_created_after timestamptz, p_after_distance double precision, p_after_id uuid, p_lim integer
    )
    RETURNS TABLE (
      id uuid, organization_id uuid, latitude double precision, longitude double precision,
      distance_m double precision, total bigint
    )
    #{@definer}
    AS $$
      SELECT m.id, m.organization_id, m.latitude, m.longitude, m.distance_m, m.total
      FROM (
        SELECT x.*, count(*) OVER () AS total
        FROM palee_around_match_clubs(p_origin, p_radius_m, p_bbox, #{tag_args(levels?)},
               p_created_after) x
      ) m
      WHERE p_after_id IS NULL OR (m.distance_m, m.id) > (p_after_distance, p_after_id)
      ORDER BY m.distance_m, m.id
      LIMIT p_lim
    $$
    """
  end

  defp posts(levels?) do
    """
    CREATE FUNCTION palee_around_posts(
      p_origin geography, p_radius_m double precision, p_bbox geography, p_since timestamptz,
      p_viewer_id uuid, #{tag_params(levels?)},
      p_created_after timestamptz, p_before_at timestamptz, p_before_id uuid, p_lim integer
    )
    RETURNS TABLE (
      id uuid, source text, organization_id uuid, author_id uuid, latitude double precision,
      longitude double precision, distance_m double precision, created_at timestamptz,
      total bigint
    )
    #{@definer}
    AS $$
      SELECT m.id, m.source, m.organization_id, m.author_id, m.latitude, m.longitude,
             m.distance_m, m.created_at, m.total
      FROM (
        SELECT x.*, count(*) OVER () AS total
        FROM palee_around_match_posts(p_origin, p_radius_m, p_bbox, p_since, p_viewer_id,
               #{tag_args(levels?)}, p_created_after) x
      ) m
      WHERE p_before_id IS NULL OR (m.created_at, m.id) < (p_before_at, p_before_id)
      ORDER BY m.created_at DESC, m.id DESC
      LIMIT p_lim
    $$
    """
  end

  defp counts(levels?) do
    """
    CREATE FUNCTION palee_around_counts(
      p_origin geography, p_radii double precision[], p_max_radius_m double precision,
      p_bbox geography, p_kinds text[], p_now_at timestamptz,
      p_win_from timestamptz[], p_win_to timestamptz[], p_max_price_cents integer, p_min_price_cents integer,
      p_trial_only boolean, p_exclude_ids uuid[], p_since timestamptz, p_viewer_id uuid,
      #{tag_params(levels?)},
      p_created_after timestamptz
    )
    RETURNS TABLE (kind text, radius_m double precision, total bigint)
    #{@definer}
    AS $$
      SELECT x.kind, r.radius_m, count(*) FILTER (WHERE x.distance_m <= r.radius_m)
      FROM (
        SELECT 'events'::text AS kind, e.distance_m
        FROM palee_around_match_events(p_origin, p_max_radius_m, p_bbox, p_now_at, p_win_from, p_win_to,
               p_max_price_cents, p_min_price_cents, #{tag_args(levels?)}, p_created_after) e
        WHERE 'events' = ANY (p_kinds)
        UNION ALL
        SELECT 'boxes', b.distance_m
        FROM palee_around_match_boxes(p_origin, p_max_radius_m, p_bbox, p_trial_only, p_exclude_ids,
               #{tag_args(levels?)}, p_created_after) b
        WHERE 'boxes' = ANY (p_kinds)
        UNION ALL
        SELECT 'clubs', c.distance_m
        FROM palee_around_match_clubs(p_origin, p_max_radius_m, p_bbox, #{tag_args(levels?)},
               p_created_after) c
        WHERE 'clubs' = ANY (p_kinds)
        UNION ALL
        SELECT 'posts', p.distance_m
        FROM palee_around_match_posts(p_origin, p_max_radius_m, p_bbox, p_since, p_viewer_id,
               #{tag_args(levels?)}, p_created_after) p
        WHERE 'posts' = ANY (p_kinds)
      ) x
      CROSS JOIN unnest(p_radii) AS r(radius_m)
      GROUP BY x.kind, r.radius_m
    $$
    """
  end

  defp pins(levels?) do
    """
    CREATE FUNCTION palee_around_pins(
      p_origin geography, p_radius_m double precision, p_bbox geography, p_kinds text[],
      p_now_at timestamptz, p_win_from timestamptz[], p_win_to timestamptz[],
      p_max_price_cents integer, p_min_price_cents integer, p_trial_only boolean, p_exclude_ids uuid[],
      p_since timestamptz, p_viewer_id uuid, #{tag_params(levels?)}, p_lim integer
    )
    RETURNS TABLE (
      kind text, id uuid, latitude double precision, longitude double precision, title text,
      slug text, distance_m double precision
    )
    #{@definer}
    AS $$
      SELECT x.kind, x.id, x.latitude, x.longitude, x.title, x.slug, x.distance_m
      FROM (
        SELECT 'events'::text AS kind, e.id, e.latitude, e.longitude, e.title,
               NULL::text AS slug, e.distance_m
        FROM palee_around_match_events(p_origin, p_radius_m, p_bbox, p_now_at, p_win_from, p_win_to,
               p_max_price_cents, p_min_price_cents, #{tag_args(levels?)}, NULL) e
        WHERE 'events' = ANY (p_kinds)
        UNION ALL
        SELECT 'boxes', b.organization_id, b.latitude, b.longitude, b.title, b.slug,
               b.distance_m
        FROM palee_around_match_boxes(p_origin, p_radius_m, p_bbox, p_trial_only, p_exclude_ids,
               #{tag_args(levels?)}, NULL) b
        WHERE 'boxes' = ANY (p_kinds)
        UNION ALL
        SELECT 'clubs', c.id, c.latitude, c.longitude, c.title, NULL, c.distance_m
        FROM palee_around_match_clubs(p_origin, p_radius_m, p_bbox, #{tag_args(levels?)}, NULL) c
        WHERE 'clubs' = ANY (p_kinds)
        UNION ALL
        SELECT 'posts', p.id, p.latitude, p.longitude, p.title, NULL, p.distance_m
        FROM palee_around_match_posts(p_origin, p_radius_m, p_bbox, p_since, p_viewer_id,
               #{tag_args(levels?)}, NULL) p
        WHERE 'posts' = ANY (p_kinds)
      ) x
      ORDER BY x.distance_m, x.id
      LIMIT p_lim
    $$
    """
  end
end
