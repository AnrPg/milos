defmodule Palee.Places.GazetteerImportRLSTest do
  @moduledoc "ADR-188: sessions may add and refresh geocoded places, never curated ones."

  use Palee.RLSCase, async: false

  @columns "id, slug, kind, name, name_en, country_code, latitude, longitude, radius_m, search_key, source, inserted_at, updated_at"

  # Each attempt in its own rolled-back transaction: nothing is left behind.
  defp attempt(conn, sql, params) do
    Postgrex.transaction(conn, fn tx ->
      result = Postgrex.query(tx, sql, params)
      Postgrex.rollback(tx, result)
    end)
    |> elem(1)
  end

  defp insert(source),
    do: """
    INSERT INTO places_neighbourhoods (#{@columns})
    VALUES (gen_random_uuid(), 'rls-test-#{source}', 'city', 'X', 'X', 'DE', 1, 1, 1000, 'x', '#{source}', now(), now())
    ON CONFLICT (slug) DO UPDATE SET name = excluded.name
    """

  test "a geocoded place can be stored and refreshed", %{conn: conn} do
    assert {:ok, %{num_rows: 1}} = attempt(conn, insert("osm"), [])
  end

  test "a curated place can be neither added nor changed", %{conn: conn} do
    assert {:error, %Postgrex.Error{postgres: %{code: :insufficient_privilege}}} =
             attempt(conn, insert("curated"), [])

    assert {:ok, %{num_rows: 0}} =
             attempt(
               conn,
               "UPDATE places_neighbourhoods SET name = 'Y' WHERE slug = 'athens-kypseli'",
               []
             )

    assert {:ok, %{num_rows: 0}} =
             attempt(
               conn,
               "UPDATE places_neighbourhoods SET source = 'osm' WHERE slug = 'athens-kypseli'",
               []
             )
  end
end
