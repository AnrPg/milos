defmodule PaleeWeb.MyInterestsControllerTest do
  use PaleeWeb.ConnCase, async: false

  import Palee.TestFixtures

  test "interests start empty, are replaced whole and stay the person's own", %{conn: conn} do
    user = user_fixture()
    other = user_fixture()

    assert %{"interests" => %{"disciplines" => [], "level" => nil}} =
             conn |> put_bearer_token(user) |> get("/api/me/interests") |> json_response(200)

    assert %{"interests" => %{"disciplines" => ["crossfit", "yoga"], "level" => "beginner"}} =
             conn
             |> recycle()
             |> put_bearer_token(user)
             |> put("/api/me/interests", %{
               "disciplines" => ["crossfit", "yoga", "crossfit"],
               "level" => "beginner"
             })
             |> json_response(200)

    assert %{"interests" => %{"disciplines" => ["running"], "level" => nil}} =
             conn
             |> recycle()
             |> put_bearer_token(user)
             |> put("/api/me/interests", %{"disciplines" => ["running"], "level" => nil})
             |> json_response(200)

    assert %{"interests" => %{"disciplines" => ["running"], "level" => nil}} =
             conn
             |> recycle()
             |> put_bearer_token(user)
             |> get("/api/me/interests")
             |> json_response(200)

    assert %{"interests" => %{"disciplines" => [], "level" => nil}} =
             conn
             |> recycle()
             |> put_bearer_token(other)
             |> get("/api/me/interests")
             |> json_response(200)
  end

  test "unknown disciplines and levels are rejected", %{conn: conn} do
    user = user_fixture()

    for body <- [
          %{"disciplines" => ["knitting"], "level" => nil},
          %{"disciplines" => ["yoga"], "level" => "elite"},
          %{"disciplines" => ["yoga"]},
          %{"disciplines" => "yoga", "level" => nil}
        ] do
      assert %{"code" => "validation_failed"} =
               conn
               |> recycle()
               |> put_bearer_token(user)
               |> put("/api/me/interests", body)
               |> json_response(422)
    end
  end

  test "the first-run is a tour the account completes once", %{conn: conn} do
    user = user_fixture()

    assert %{"completed_tours" => ["first_run"]} =
             conn
             |> put_bearer_token(user)
             |> post("/api/me/tours/first_run/complete")
             |> json_response(200)

    assert %{"completed_tours" => ["first_run"]} =
             conn
             |> recycle()
             |> put_bearer_token(user)
             |> get("/api/auth/me")
             |> json_response(200)
  end
end
