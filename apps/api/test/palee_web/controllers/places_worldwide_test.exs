defmodule PaleeWeb.PlacesWorldwideTest do
  @moduledoc """
  ADR-188: area search covers the world. Stored places come first, the
  geocoder fills in places and addresses anywhere, a picked suggestion is
  stored once and an address becomes the
  neighbourhood around it, never the address itself.
  """

  use PaleeWeb.ConnCase, async: false

  import Palee.TestFixtures

  setup %{conn: conn} do
    %{conn: put_bearer_token(conn, user_fixture())}
  end

  defp send_json(conn, method, path, body) do
    conn
    |> put_req_header("content-type", "application/json")
    |> dispatch(@endpoint, method, path, Jason.encode!(body))
  end

  defp search(conn, q) do
    conn
    |> get("/api/places/neighbourhoods?q=" <> URI.encode_www_form(q))
    |> json_response(200)
  end

  defp import!(conn, ref) do
    conn
    |> send_json(:post, "/api/places/neighbourhoods/import", %{ref: ref})
    |> json_response(200)
    |> Map.fetch!("neighbourhood")
  end

  test "a city anywhere: suggested with both names, stored once under the id it was suggested with",
       %{conn: conn} do
    assert %{"remote" => "ok", "neighbourhoods" => [munich]} = search(conn, "München")

    assert %{
             "kind" => "city",
             "name" => "München",
             "name_en" => "Munich",
             "context" => "Bayern, Deutschland",
             "context_en" => "Bavaria, Germany",
             "ref" => ref
           } = munich

    stored = import!(conn, ref)
    assert stored["id"] == munich["id"]
    assert stored["slug"] == "osm-r62428"
    refute Map.has_key?(stored, "ref")

    # Importing again refreshes the same row.
    assert import!(conn, ref)["id"] == munich["id"]

    # Now it is a stored place: found locally, in English too, and savable.
    assert %{"neighbourhoods" => [%{"id" => id} = local]} = search(conn, "munich")
    assert id == munich["id"]
    refute local["ref"]

    assert %{"neighbourhoods" => [%{"name_en" => "Munich"}]} =
             conn
             |> send_json(:put, "/api/me/around/area", %{neighbourhood_ids: [id]})
             |> json_response(200)
  end

  test "an address becomes the neighbourhood around it", %{conn: conn} do
    assert %{"neighbourhoods" => [%{"kind" => "address", "ref" => ref} = address]} =
             search(conn, "Oranienstraße 10")

    assert address["name"] == "Oranienstraße 10"
    assert address["context"] == "Kreuzberg, Berlin, Deutschland"

    area = import!(conn, ref)
    assert %{"kind" => "neighbourhood", "name" => "Kreuzberg", "slug" => "osm-r55764"} = area
    assert area["latitude"] == 52.4986
  end

  test "stored places come first and nearby namesakes from the geocoder are dropped",
       %{conn: conn} do
    assert %{"neighbourhoods" => places} = search(conn, "Κυψ")
    assert Enum.all?(places, &is_nil(&1["ref"]))
    assert Enum.any?(places, &(&1["slug"] == "athens-kypseli"))
  end

  test "the geocoder is optional: down means stored places only; short queries skip it",
       %{conn: conn} do
    assert %{"remote" => "unavailable", "neighbourhoods" => []} = search(conn, "down town")
    assert %{"remote" => "skipped"} = search(conn, "mü")

    # English names are a bonus; local results still come.
    assert %{"remote" => "ok", "neighbourhoods" => [%{"name_en" => "München"}]} =
             search(conn, "halfdown")
  end

  test "a forged or tampered ref is refused", %{conn: conn} do
    for ref <- ["nope", String.duplicate("a", 50)] do
      assert %{"code" => "invalid_place_ref"} =
               conn
               |> send_json(:post, "/api/places/neighbourhoods/import", %{ref: ref})
               |> json_response(422)
    end
  end
end
