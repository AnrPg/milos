defmodule PaleeWeb.MeTourControllerTest do
  use PaleeWeb.ConnCase, async: false

  import Palee.TestFixtures

  test "tour completion is stored on the account and returned by /auth/me", %{conn: conn} do
    user = user_fixture()

    assert %{"completed_tours" => []} =
             conn |> put_bearer_token(user) |> get("/api/auth/me") |> json_response(200)

    assert %{"completed_tours" => ["member"]} =
             conn
             |> recycle()
             |> put_bearer_token(user)
             |> post("/api/me/tours/member/complete")
             |> json_response(200)

    # Idempotent, and visible from any device through /auth/me.
    conn |> recycle() |> put_bearer_token(user) |> post("/api/me/tours/member/complete")

    assert %{"completed_tours" => ["member"]} =
             conn
             |> recycle()
             |> put_bearer_token(user)
             |> get("/api/auth/me")
             |> json_response(200)
  end

  test "unknown tours are rejected", %{conn: conn} do
    user = user_fixture()

    assert %{"code" => "invalid_tour"} =
             conn
             |> put_bearer_token(user)
             |> post("/api/me/tours/everything/complete")
             |> json_response(422)
  end
end
