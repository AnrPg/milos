defmodule Palee.Repo.Migrations.FuzzyPeopleSearch do
  @moduledoc """
  People search forgives typos (ANR 2026-10-25): besides the handle prefix
  and the name substring of ADR-193 §4, `palee_people_search` matches a name
  or handle whose trigram word similarity is at least 0.5, from three
  characters on. Literal matches still come before close ones within each
  relation rank, closest first.

  The threshold is an explicit `word_similarity(...) >= 0.5` comparison, never
  the `pg_trgm.word_similarity_threshold` setting behind `<%`: a function-level
  `SET` of an extension parameter needs superuser rights at `CREATE FUNCTION`
  time, which the production migration role does not have (this migration
  failed in prod with 42501 on 2026-10-26), and a session setting would leak
  into callers. Each match arm stays index-backed: the literal arms use the
  GIN trigram indexes, the fuzzy arms walk new GiST trigram indexes nearest
  first (`<<->`, the word-similarity distance) and stop after 500 rows.
  """

  use Ecto.Migration

  @threshold "0.5"
  @me "NULLIF(current_setting('app.user_id', true), '')::uuid"

  def up do
    execute("""
    CREATE INDEX IF NOT EXISTS users_search_text_trgm_gist_index
      ON users USING gist (search_text gist_trgm_ops)
    """)

    execute("""
    CREATE INDEX IF NOT EXISTS users_handle_trgm_gist_index
      ON users USING gist (nickname gist_trgm_ops)
    """)

    execute("""
    CREATE OR REPLACE FUNCTION palee_people_search(handle_term text, name_term text, lim integer)
    RETURNS TABLE (user_id uuid, relation text)
    LANGUAGE sql
    STABLE SECURITY DEFINER
    SET search_path = public, pg_temp
    AS $function$
      WITH me AS (SELECT #{@me} AS id),
      terms AS (
        SELECT
          CASE WHEN length(COALESCE(handle_term, '')) < 1 THEN NULL
            ELSE replace(replace(replace(handle_term, '\\', '\\\\'), '%', '\\%'), '_', '\\_') || '%'
          END AS handle_p,
          CASE WHEN length(COALESCE(name_term, '')) < 2 THEN NULL
            ELSE '%' || replace(replace(replace(name_term, '\\', '\\\\'), '%', '\\%'), '_', '\\_') || '%'
          END AS name_p,
          CASE WHEN length(COALESCE(name_term, '')) < 3 THEN NULL ELSE name_term END AS fuzzy
      ),
      matches AS (
        SELECT u.id FROM users u WHERE u.nickname LIKE (SELECT handle_p FROM terms)
        UNION
        SELECT u.id FROM users u WHERE u.search_text LIKE (SELECT name_p FROM terms)
        UNION
        SELECT near.id FROM (
          SELECT u.id, word_similarity(name_term, u.search_text) AS closeness
          FROM users u
          WHERE length(name_term) >= 3 AND u.demo_organization_id IS NULL
          ORDER BY name_term <<-> u.search_text
          LIMIT 500
        ) near
        WHERE near.closeness >= #{@threshold}
        UNION
        SELECT near.id FROM (
          SELECT u.id, word_similarity(handle_term, u.nickname) AS closeness
          FROM users u
          WHERE length(handle_term) >= 3 AND u.demo_organization_id IS NULL
          ORDER BY handle_term <<-> u.nickname
          LIMIT 500
        ) near
        WHERE near.closeness >= #{@threshold}
      ),
      candidates AS (
        SELECT u.id, u.nickname,
          (u.nickname LIKE (SELECT handle_p FROM terms)
            OR u.search_text LIKE (SELECT name_p FROM terms)) AS literal,
          GREATEST(
            COALESCE(word_similarity((SELECT fuzzy FROM terms), u.search_text), 0),
            COALESCE(word_similarity(handle_term, u.nickname), 0)) AS closeness
        FROM users u
        WHERE (SELECT id FROM me) IS NOT NULL
          AND u.id IN (SELECT id FROM matches)
          AND u.id <> (SELECT id FROM me)
          AND u.demo_organization_id IS NULL
          AND u.id NOT IN (
            SELECT b.blocked_user_id FROM community_user_blocks b WHERE b.user_id = (SELECT id FROM me)
            UNION
            SELECT b.user_id FROM community_user_blocks b WHERE b.blocked_user_id = (SELECT id FROM me))
        ORDER BY 3 DESC, 4 DESC
        LIMIT 500
      ),
      facts AS (
        SELECT c.id, c.nickname, c.literal, c.closeness,
          COALESCE(s.private_account, false) AS private,
          COALESCE(s.searchable, true) AS searchable,
          COALESCE(s.hide_from_members, false) AS hidden_member,
          r.shares_club, r.i_follow, r.follows_me, r.nearby
        FROM candidates c
        LEFT JOIN community_social_settings s ON s.user_id = c.id
        JOIN palee_person_relations(ARRAY(SELECT id FROM candidates)) r ON r.user_id = c.id
      ),
      ranked AS (
        SELECT f.id, f.nickname, f.literal, f.closeness,
          CASE
            WHEN f.shares_club AND (NOT f.hidden_member OR f.searchable) THEN 1
            WHEN f.i_follow AND f.follows_me THEN 2
            WHEN f.i_follow OR f.follows_me THEN 3
            WHEN NOT f.private AND f.searchable AND f.nearby THEN 4
            WHEN NOT f.private AND f.searchable THEN 5
          END AS rank
        FROM facts f
      )
      SELECT ranked.id,
        CASE ranked.rank WHEN 1 THEN 'club' WHEN 2 THEN 'buddy' WHEN 3 THEN 'follow'
          WHEN 4 THEN 'nearby' ELSE 'public' END
      FROM ranked
      WHERE ranked.rank IS NOT NULL
      ORDER BY ranked.rank,
        CASE WHEN ranked.nickname = handle_term THEN 0 ELSE 1 END,
        CASE WHEN ranked.literal THEN 0 ELSE 1 END,
        ranked.closeness DESC,
        ranked.nickname
      LIMIT LEAST(GREATEST(lim, 1), 50)
    $function$
    """)
  end

  def down do
    execute("DROP INDEX IF EXISTS users_handle_trgm_gist_index")
    execute("DROP INDEX IF EXISTS users_search_text_trgm_gist_index")

    execute("""
    CREATE OR REPLACE FUNCTION palee_people_search(handle_term text, name_term text, lim integer)
    RETURNS TABLE (user_id uuid, relation text)
    LANGUAGE sql
    STABLE SECURITY DEFINER
    SET search_path = public, pg_temp
    AS $function$
      WITH me AS (SELECT #{@me} AS id),
      terms AS (
        SELECT
          CASE WHEN length(COALESCE(handle_term, '')) < 1 THEN NULL
            ELSE replace(replace(replace(handle_term, '\\', '\\\\'), '%', '\\%'), '_', '\\_') || '%'
          END AS handle_p,
          CASE WHEN length(COALESCE(name_term, '')) < 2 THEN NULL
            ELSE '%' || replace(replace(replace(name_term, '\\', '\\\\'), '%', '\\%'), '_', '\\_') || '%'
          END AS name_p
      ),
      candidates AS (
        SELECT u.id, u.nickname
        FROM users u
        WHERE (SELECT id FROM me) IS NOT NULL
          AND u.id <> (SELECT id FROM me)
          AND u.demo_organization_id IS NULL
          AND ((SELECT handle_p FROM terms) IS NOT NULL OR (SELECT name_p FROM terms) IS NOT NULL)
          AND (u.nickname LIKE (SELECT handle_p FROM terms)
            OR u.search_text LIKE (SELECT name_p FROM terms))
          AND u.id NOT IN (
            SELECT b.blocked_user_id FROM community_user_blocks b WHERE b.user_id = (SELECT id FROM me)
            UNION
            SELECT b.user_id FROM community_user_blocks b WHERE b.blocked_user_id = (SELECT id FROM me))
        LIMIT 500
      ),
      facts AS (
        SELECT c.id, c.nickname,
          COALESCE(s.private_account, true) AS private,
          COALESCE(s.searchable, true) AS searchable,
          COALESCE(s.hide_from_members, false) AS hidden_member,
          r.shares_club, r.i_follow, r.follows_me, r.nearby
        FROM candidates c
        LEFT JOIN community_social_settings s ON s.user_id = c.id
        JOIN palee_person_relations(ARRAY(SELECT id FROM candidates)) r ON r.user_id = c.id
      ),
      ranked AS (
        SELECT f.id, f.nickname,
          CASE
            WHEN f.shares_club AND (NOT f.hidden_member OR f.searchable) THEN 1
            WHEN f.i_follow AND f.follows_me THEN 2
            WHEN f.i_follow OR f.follows_me THEN 3
            WHEN NOT f.private AND f.searchable AND f.nearby THEN 4
            WHEN NOT f.private AND f.searchable THEN 5
          END AS rank
        FROM facts f
      )
      SELECT ranked.id,
        CASE ranked.rank WHEN 1 THEN 'club' WHEN 2 THEN 'buddy' WHEN 3 THEN 'follow'
          WHEN 4 THEN 'nearby' ELSE 'public' END
      FROM ranked
      WHERE ranked.rank IS NOT NULL
      ORDER BY ranked.rank,
        CASE WHEN ranked.nickname = handle_term THEN 0 ELSE 1 END,
        ranked.nickname
      LIMIT LEAST(GREATEST(lim, 1), 50)
    $function$
    """)
  end
end
