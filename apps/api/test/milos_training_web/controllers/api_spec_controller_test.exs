defmodule MilosTrainingWeb.ApiSpecControllerTest do
  use MilosTrainingWeb.ConnCase, async: true

  describe "GET /api/openapi" do
    test "includes the auth and admin contract", %{conn: conn} do
      conn = get(conn, "/api/openapi")
      body = json_response(conn, 200)

      assert Map.has_key?(body["paths"], "/api/auth/register")
      assert Map.has_key?(body["paths"], "/api/auth/login")
      assert Map.has_key?(body["paths"], "/api/auth/refresh")
      assert Map.has_key?(body["paths"], "/api/auth/me")
      assert Map.has_key?(body["paths"], "/api/admin/users/{id}/role")

      assert get_in(body, ["paths", "/api/auth/register", "post", "requestBody", "required"]) ==
               true

      assert get_in(body, ["paths", "/api/auth/login", "post", "requestBody", "required"]) == true

      assert get_in(body, ["paths", "/api/auth/refresh", "post", "requestBody", "required"]) ==
               true

      assert get_in(body, [
               "paths",
               "/api/admin/users/{id}/role",
               "patch",
               "requestBody",
               "required"
             ]) == true

      refresh_properties =
        get_in(body, [
          "paths",
          "/api/auth/refresh",
          "post",
          "responses",
          "200",
          "content",
          "application/json",
          "schema",
          "properties"
        ])

      assert Map.has_key?(refresh_properties, "access_token")
      assert Map.has_key?(refresh_properties, "refresh_token")
      assert get_in(body, ["paths", "/api/auth/login", "post", "responses", "429"]) != nil
      assert get_in(body, ["paths", "/api/auth/refresh", "post", "responses", "503"]) != nil

      assert get_in(body, ["paths", "/api/admin/users/{id}/role", "patch", "responses", "403"]) !=
               nil
    end
  end
end
