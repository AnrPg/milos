defmodule MilosTrainingWeb.SavedFilterControllerTest do
  @moduledoc "ADR-151 remembered and named filters, as the RLS runtime role."

  use MilosTrainingWeb.ConnCase, async: false

  import MilosTraining.TestFixtures

  setup do
    %{user: user_fixture(), other: user_fixture()}
  end

  test "remembers the last filter and saves named ones per surface", ctx do
    conn = put_bearer_token(ctx.conn, ctx.user)

    assert %{"last_used" => nil, "saved" => []} =
             conn |> get("/api/me/filters/around_me") |> json_response(200)

    put(conn, "/api/me/filters/around_me/last-used", %{params: %{radius_km: 3}})
    |> json_response(200)

    assert %{"last_used" => %{"radius_km" => 5.0, "v" => 1}} =
             conn
             |> put("/api/me/filters/around_me/last-used", %{params: %{radius_km: 5}})
             |> json_response(200)

    %{"saved" => [%{"id" => id, "name" => "ΣΚ κοντά"}]} =
      conn
      |> post("/api/me/filters/around_me", %{name: " ΣΚ  κοντά ", params: %{when: "weekend"}})
      |> json_response(200)

    assert %{"saved" => [%{"id" => ^id, "params" => %{"when" => "today"}}]} =
             conn
             |> post("/api/me/filters/around_me", %{name: "σκ κοντά", params: %{when: "today"}})
             |> json_response(200)

    assert %{"last_used" => nil, "saved" => []} =
             ctx.conn
             |> put_bearer_token(ctx.other)
             |> get("/api/me/filters/around_me")
             |> json_response(200)

    ctx.conn
    |> put_bearer_token(ctx.other)
    |> delete("/api/me/filters/around_me/#{id}")
    |> json_response(404)

    assert %{"saved" => []} =
             conn |> delete("/api/me/filters/around_me/#{id}") |> json_response(200)
  end

  test "rejects unknown surfaces and oversized params", ctx do
    conn = put_bearer_token(ctx.conn, ctx.user)
    conn |> get("/api/me/filters/nowhere") |> json_response(422)

    conn
    |> put("/api/me/filters/feed/last-used", %{params: %{x: String.duplicate("a", 5_000)}})
    |> json_response(422)
  end
end
