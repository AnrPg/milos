defmodule Palee.Infrastructure.Database.FunctionSettingsTest do
  @moduledoc """
  The production migration role is not a superuser, and `CREATE FUNCTION ...
  SET <parameter>` of an extension parameter (such as
  `pg_trgm.word_similarity_threshold`) needs superuser rights whenever the
  extension's library is not yet loaded in the session, which made
  20261221100000 fail in prod on 2026-10-26. Functions may pin `search_path`
  (SECURITY DEFINER hygiene) and nothing else; thresholds belong in the query.
  Extension functions (PostGIS) are the administrator's and are left out.
  """

  use Palee.DataCase, async: true

  test "database functions pin only search_path" do
    %{rows: rows} =
      Repo.query!("""
      SELECT p.proname, setting
      FROM pg_proc p
      CROSS JOIN LATERAL unnest(p.proconfig) AS setting
      WHERE p.pronamespace = 'public'::regnamespace
        AND split_part(setting, '=', 1) <> 'search_path'
        AND NOT EXISTS (
          SELECT 1 FROM pg_depend d
          WHERE d.classid = 'pg_proc'::regclass AND d.objid = p.oid AND d.deptype = 'e')
      ORDER BY 1, 2
      """)

    assert rows == []
  end
end
