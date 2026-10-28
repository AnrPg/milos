defmodule Palee.Repo.Migrations.BoxNameSearch do
  @moduledoc """
  ADR-216: find a box (or an independent coach) by name.

  `palee_fold_name/1` folds a name the way `Palee.Identity.Domain.NameSearch`
  folds a query (NFKD, combining marks stripped, lower-case, spaces
  collapsed), so «Τολάρας», "τολαρας" and "ΤΟΛΑΡΑΣ" meet.

  `palee_search_public_boxes/2` reads the same rows a visitor may see
  (`palee_public_boxes`: an active, live business that published its page)
  and matches every folded term against its name, its brand name and its
  slug (the slug is the Latin form of the name, ADR-170, so "tolaras" finds
  «Τολάρας»). Names that start with a term rank first, then names with a
  word that starts with it, then the rest; from three characters a close
  spelling also answers, after every literal match (pg_trgm word similarity
  ≥ 0.5 as an explicit comparison, like people and club search, ANR
  2026-10-25: never the `<%` operator, whose threshold is a GUC). SECURITY DEFINER like
  the other public lookups, pinned to `search_path` only.
  """

  use Ecto.Migration

  def up do
    execute("""
    CREATE FUNCTION palee_fold_name(value text)
     RETURNS text
     LANGUAGE sql
     IMMUTABLE PARALLEL SAFE
    AS $function$
      SELECT btrim(regexp_replace(
               lower(regexp_replace(normalize(COALESCE(value, ''), NFKD), '[\\u0300-\\u036f]', '', 'g')),
               '\\s+', ' ', 'g'))
    $function$
    """)

    execute("""
    CREATE FUNCTION palee_search_public_boxes(p_terms text[], p_lim integer)
     RETURNS TABLE(organization_id uuid, slug text, name text, logo_url text, primary_color text,
                   provider_kind text, neighbourhood text, city text)
     LANGUAGE sql
     STABLE SECURITY DEFINER
     SET search_path TO 'public', 'pg_temp'
    AS $function$
      SELECT f.id, f.slug, f.name, f.logo_url, f.primary_color, f.provider_kind,
             l.neighbourhood::text, l.city::text
      FROM (
        SELECT o.id, o.slug::text AS slug,
               COALESCE(NULLIF(btrim(s.brand_name), ''), o.name)::text AS name,
               s.brand_logo_url::text AS logo_url, s.brand_primary_color::text AS primary_color,
               o.provider_kind::text AS provider_kind,
               ' ' || palee_fold_name(concat_ws(' ', s.brand_name, o.name)) AS name_key,
               palee_fold_name(o.slug::text) AS slug_key
        FROM public.organizations o
        JOIN public.organization_public_profiles p
          ON p.organization_id = o.id AND p.published_at IS NOT NULL
        LEFT JOIN public.organization_settings s ON s.organization_id = o.id
        WHERE o.status = 'active' AND o.activation = 'active'
      ) f
      CROSS JOIN LATERAL (
        SELECT CASE
                 WHEN bool_or(starts_with(f.name_key, ' ' || t) OR starts_with(f.slug_key, t)) THEN 0
                 WHEN bool_or(strpos(f.name_key, ' ' || t) > 0) THEN 1
                 ELSE 2
               END AS rank,
               bool_or(strpos(f.name_key, t) > 0 OR strpos(f.slug_key, t) > 0) AS hit,
               max(GREATEST(word_similarity(t, f.name_key), word_similarity(t, f.slug_key)))
                 FILTER (WHERE char_length(t) >= 3) AS closeness
        FROM unnest(p_terms) t
        WHERE t <> ''
      ) m
      LEFT JOIN LATERAL (
        SELECT fl.neighbourhood, fl.city
        FROM public.facility_locations fl
        WHERE fl.organization_id = f.id AND fl.archived_at IS NULL
        ORDER BY fl.inserted_at, fl.id
        LIMIT 1
      ) l ON true
      WHERE m.hit OR m.closeness >= 0.5
      ORDER BY CASE WHEN m.hit THEN m.rank ELSE 3 END, m.closeness DESC NULLS LAST, f.name, f.id
      LIMIT p_lim
    $function$
    """)
  end

  def down do
    execute("DROP FUNCTION IF EXISTS palee_search_public_boxes(text[], integer)")
    execute("DROP FUNCTION IF EXISTS palee_fold_name(text)")
  end
end
