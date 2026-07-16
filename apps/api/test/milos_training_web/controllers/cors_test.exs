defmodule MilosTrainingWeb.CorsTest do
  use MilosTrainingWeb.ConnCase, async: true

  test "handles preflight requests for allowed Milos web origins", %{conn: conn} do
    conn =
      conn
      |> put_req_header("origin", "http://localhost:18300")
      |> put_req_header("access-control-request-method", "POST")
      |> put_req_header("access-control-request-headers", "authorization,content-type")
      |> options("/api/auth/register")

    assert response(conn, 204) == ""
    assert get_resp_header(conn, "access-control-allow-origin") == ["http://localhost:18300"]

    assert get_resp_header(conn, "access-control-allow-methods") == [
             "GET,POST,PUT,PATCH,DELETE,OPTIONS"
           ]

    assert get_resp_header(conn, "access-control-allow-headers") == ["authorization,content-type"]
  end

  test "adds cors headers on normal api responses for allowed Milos web origins", %{conn: conn} do
    conn =
      conn
      |> put_req_header("origin", "http://localhost:18300")
      |> get("/api/openapi")

    assert is_map(json_response(conn, 200)["paths"])
    assert get_resp_header(conn, "access-control-allow-origin") == ["http://localhost:18300"]
  end

  test "does not approve unknown origins", %{conn: conn} do
    conn =
      conn
      |> put_req_header("origin", "http://localhost:9999")
      |> get("/api/openapi")

    assert is_map(json_response(conn, 200)["paths"])
    assert get_resp_header(conn, "access-control-allow-origin") == []
  end
end
