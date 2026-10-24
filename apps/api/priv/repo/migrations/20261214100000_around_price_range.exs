defmodule Palee.Repo.Migrations.AroundPriceRange do
  @moduledoc """
  Γύρω μου price range (ADR-154 amendment): events can be narrowed from a
  minimum price as well as up to a maximum. `palee_around_match_events`
  and the three definers that read it (`palee_around_events`,
  `palee_around_counts`, `palee_around_pins`) take `p_min_price_cents`
  right after `p_max_price_cents`; NULL leaves that end open.

  The bodies are those of `20261024100000_around_me` (match_events as
  `20261206100000_business_activation` left it, live organizations only);
  `down` renders them again without the minimum.
  """

  use Ecto.Migration

  @live "AND o.activation = 'active'"
  @definer "LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp"

  def up, do: replace(false, true)
  def down, do: replace(true, false)

  defp replace(from_min?, to_min?) do
    for {name, args} <- signatures(from_min?), do: execute("DROP FUNCTION IF EXISTS #{name}(#{args})")

    execute(match_events(to_min?))
    execute(events(to_min?))
    execute(counts(to_min?))
    execute(pins(to_min?))
  end

  # Argument types only, as DROP FUNCTION needs them.
  defp signatures(min?) do
    price = if min?, do: "integer, integer", else: "integer"

    [
      {"palee_around_events",
       "geography, double precision, geography, timestamptz, timestamptz[], timestamptz[], #{price}, " <>
         "text[], text[], text[], text[], timestamptz, timestamptz, uuid, integer"},
      {"palee_around_counts",
       "geography, double precision[], double precision, geography, text[], timestamptz, timestamptz[], " <>
         "timestamptz[], #{price}, boolean, uuid[], timestamptz, uuid, text[], text[], text[], text[], timestamptz"},
      {"palee_around_pins",
       "geography, double precision, geography, text[], timestamptz, timestamptz[], timestamptz[], #{price}, " <>
         "boolean, uuid[], timestamptz, uuid, text[], text[], text[], text[], integer"},
      {"palee_around_match_events",
       "geography, double precision, geography, timestamptz, timestamptz[], timestamptz[], #{price}, " <>
         "text[], text[], text[], text[], timestamptz"}
    ]
  end

  defp price_param(true), do: "p_max_price_cents integer, p_min_price_cents integer"
  defp price_param(false), do: "p_max_price_cents integer"

  defp price_arg(true), do: "p_max_price_cents, p_min_price_cents"
  defp price_arg(false), do: "p_max_price_cents"

  defp min_clause(true), do: "\n        AND (p_min_price_cents IS NULL OR e.price_cents >= p_min_price_cents)"
  defp min_clause(false), do: ""

  defp match_events(min?) do
    """
    CREATE FUNCTION palee_around_match_events(p_origin geography, p_radius_m double precision, p_bbox geography, p_now_at timestamp with time zone, p_win_from timestamp with time zone[], p_win_to timestamp with time zone[], #{price_param(min?)}, p_disciplines text[], p_audiences text[], p_languages text[], p_amenities text[], p_created_after timestamp with time zone)
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
        AND (p_max_price_cents IS NULL OR e.price_cents <= p_max_price_cents)#{min_clause(min?)}
        AND (p_created_after IS NULL OR e.inserted_at > p_created_after)
        AND palee_around_tags_match(pr.published_snapshot, p_disciplines, p_audiences, p_languages, p_amenities)
    $function$
    """
  end

  defp events(min?) do
    """
    CREATE FUNCTION palee_around_events(
      p_origin geography, p_radius_m double precision, p_bbox geography, p_now_at timestamptz,
      p_win_from timestamptz[], p_win_to timestamptz[], #{price_param(min?)},
      p_disciplines text[], p_audiences text[], p_languages text[], p_amenities text[],
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
               #{price_arg(min?)}, p_disciplines, p_audiences, p_languages, p_amenities, p_created_after) x
      ) m
      WHERE p_after_id IS NULL OR (m.starts_at, m.id) > (p_after_starts_at, p_after_id)
      ORDER BY m.starts_at, m.id
      LIMIT p_lim
    $$
    """
  end

  defp counts(min?) do
    """
    CREATE FUNCTION palee_around_counts(
      p_origin geography, p_radii double precision[], p_max_radius_m double precision,
      p_bbox geography, p_kinds text[], p_now_at timestamptz,
      p_win_from timestamptz[], p_win_to timestamptz[], #{price_param(min?)},
      p_trial_only boolean, p_exclude_ids uuid[], p_since timestamptz, p_viewer_id uuid,
      p_disciplines text[], p_audiences text[], p_languages text[], p_amenities text[],
      p_created_after timestamptz
    )
    RETURNS TABLE (kind text, radius_m double precision, total bigint)
    #{@definer}
    AS $$
      SELECT x.kind, r.radius_m, count(*) FILTER (WHERE x.distance_m <= r.radius_m)
      FROM (
        SELECT 'events'::text AS kind, e.distance_m
        FROM palee_around_match_events(p_origin, p_max_radius_m, p_bbox, p_now_at, p_win_from, p_win_to,
               #{price_arg(min?)}, p_disciplines, p_audiences, p_languages, p_amenities, p_created_after) e
        WHERE 'events' = ANY (p_kinds)
        UNION ALL
        SELECT 'boxes', b.distance_m
        FROM palee_around_match_boxes(p_origin, p_max_radius_m, p_bbox, p_trial_only, p_exclude_ids,
               p_disciplines, p_audiences, p_languages, p_amenities, p_created_after) b
        WHERE 'boxes' = ANY (p_kinds)
        UNION ALL
        SELECT 'clubs', c.distance_m
        FROM palee_around_match_clubs(p_origin, p_max_radius_m, p_bbox, p_disciplines, p_audiences,
               p_languages, p_amenities, p_created_after) c
        WHERE 'clubs' = ANY (p_kinds)
        UNION ALL
        SELECT 'posts', p.distance_m
        FROM palee_around_match_posts(p_origin, p_max_radius_m, p_bbox, p_since, p_viewer_id,
               p_disciplines, p_audiences, p_languages, p_amenities, p_created_after) p
        WHERE 'posts' = ANY (p_kinds)
      ) x
      CROSS JOIN unnest(p_radii) AS r(radius_m)
      GROUP BY x.kind, r.radius_m
    $$
    """
  end

  defp pins(min?) do
    """
    CREATE FUNCTION palee_around_pins(
      p_origin geography, p_radius_m double precision, p_bbox geography, p_kinds text[],
      p_now_at timestamptz, p_win_from timestamptz[], p_win_to timestamptz[],
      #{price_param(min?)}, p_trial_only boolean, p_exclude_ids uuid[], p_since timestamptz,
      p_viewer_id uuid, p_disciplines text[], p_audiences text[], p_languages text[],
      p_amenities text[], p_lim integer
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
               #{price_arg(min?)}, p_disciplines, p_audiences, p_languages, p_amenities, NULL) e
        WHERE 'events' = ANY (p_kinds)
        UNION ALL
        SELECT 'boxes', b.organization_id, b.latitude, b.longitude, b.title, b.slug,
               b.distance_m
        FROM palee_around_match_boxes(p_origin, p_radius_m, p_bbox, p_trial_only, p_exclude_ids,
               p_disciplines, p_audiences, p_languages, p_amenities, NULL) b
        WHERE 'boxes' = ANY (p_kinds)
        UNION ALL
        SELECT 'clubs', c.id, c.latitude, c.longitude, c.title, NULL, c.distance_m
        FROM palee_around_match_clubs(p_origin, p_radius_m, p_bbox, p_disciplines, p_audiences,
               p_languages, p_amenities, NULL) c
        WHERE 'clubs' = ANY (p_kinds)
        UNION ALL
        SELECT 'posts', p.id, p.latitude, p.longitude, p.title, NULL, p.distance_m
        FROM palee_around_match_posts(p_origin, p_radius_m, p_bbox, p_since, p_viewer_id,
               p_disciplines, p_audiences, p_languages, p_amenities, NULL) p
        WHERE 'posts' = ANY (p_kinds)
      ) x
      ORDER BY x.distance_m, x.id
      LIMIT p_lim
    $$
    """
  end
end
