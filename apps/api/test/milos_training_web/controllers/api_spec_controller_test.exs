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

    test "publishes aligned admin drill-down contracts", %{conn: conn} do
      conn = get(conn, "/api/openapi")
      body = json_response(conn, 200)

      finance_schema =
        get_in(body, [
          "paths",
          "/api/admin/finance/members/{id}",
          "get",
          "responses",
          "200",
          "content",
          "application/json",
          "schema",
          "properties",
          "drill_down"
        ])

      coaching_schema =
        get_in(body, [
          "paths",
          "/api/admin/athletes/{id}/drill-down",
          "get",
          "responses",
          "200",
          "content",
          "application/json",
          "schema",
          "properties",
          "drill_down"
        ])

      assert finance_schema["required"] == [
               "identity",
               "current_status",
               "package_relationship",
               "financial_timeline",
               "outstanding_items",
               "operational_context",
               "actions"
             ]

      assert coaching_schema["required"] == [
               "identity",
               "recent_activity",
               "assigned_workouts",
               "execution_history",
               "score_trends",
               "notes_context",
               "attention_cues",
               "actions"
             ]

      assert_schema_properties(finance_schema, ["identity", "current_status", "actions"])
      assert_schema_properties(coaching_schema, ["identity", "recent_activity", "actions"])

      assert_schema_properties(finance_schema["properties"]["current_status"], [
        "state",
        "reason",
        "urgency"
      ])

      assert_schema_properties(coaching_schema["properties"]["recent_activity"], [
        "state",
        "reason",
        "urgency"
      ])

      assert_action_item_schema(finance_schema["properties"]["actions"])
      assert_action_item_schema(coaching_schema["properties"]["actions"])

      assert get_in(body, [
               "paths",
               "/api/admin/finance/members/{id}",
               "get",
               "responses",
               "404"
             ])

      assert get_in(body, [
               "paths",
               "/api/admin/finance/members/{id}",
               "get",
               "responses",
               "403"
             ])

      assert get_in(body, [
               "paths",
               "/api/admin/athletes/{id}/drill-down",
               "get",
               "responses",
               "404"
             ])

      assert get_in(body, [
               "paths",
               "/api/admin/athletes/{id}/drill-down",
               "get",
               "responses",
               "403"
             ])
    end
  end

  defp assert_schema_properties(schema, properties) do
    Enum.each(properties, fn property ->
      assert Map.has_key?(schema["properties"], property)
    end)
  end

  defp assert_action_item_schema(actions_schema) do
    item_schema = actions_schema["items"]

    assert item_schema["required"] == ["key", "available", "reason"]
    assert_schema_properties(item_schema, ["key", "available", "reason"])
  end
end
