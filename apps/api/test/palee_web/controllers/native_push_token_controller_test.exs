defmodule PaleeWeb.NativePushTokenControllerTest do
  # ADR-171: store app installs register their push tokens next to web push.
  use PaleeWeb.ConnCase, async: false

  alias Palee.FakeNativePushSender
  alias Palee.Notifications

  import Palee.TestFixtures

  @fcm_token "fcm-token-" <> String.duplicate("a", 40)
  @apns_token String.duplicate("ab", 32)

  setup do
    on_exit(&FakeNativePushSender.disable/0)
    user = user_fixture()

    conn =
      build_conn()
      |> put_bearer_token(user)
      |> Plug.Conn.put_req_header("content-type", "application/json")

    {:ok, conn: conn, user: user}
  end

  test "without credentials the provider is off and nothing is stored", %{conn: conn, user: user} do
    response =
      conn
      |> post("/api/notifications/native-push-tokens", %{
        provider: "fcm",
        platform: "android",
        token: @fcm_token
      })
      |> json_response(503)

    assert response["code"] == "native_push_not_configured"
    assert Notifications.list_native_push_tokens(user.id) == []

    assert %{"native_providers" => []} =
             conn |> get("/api/notifications/push-config") |> json_response(200)
  end

  test "registers an Android token once and refreshes it after", %{conn: conn, user: user} do
    FakeNativePushSender.enable([:fcm])

    assert %{"native_providers" => ["fcm"]} =
             conn |> get("/api/notifications/push-config") |> json_response(200)

    params = %{
      provider: "fcm",
      platform: "android",
      token: @fcm_token,
      app_id: "app.palee.member",
      app_version: "1.0.0"
    }

    created =
      conn
      |> post("/api/notifications/native-push-tokens", params)
      |> json_response(201)

    assert %{"provider" => "fcm", "platform" => "android", "app_version" => "1.0.0"} =
             created["native_push_token"]

    refute Map.has_key?(created["native_push_token"], "token")

    updated =
      conn
      |> post("/api/notifications/native-push-tokens", %{params | app_version: "1.1.0"})
      |> json_response(200)

    assert updated["native_push_token"]["id"] == created["native_push_token"]["id"]

    assert [%{app_version: "1.1.0", token: @fcm_token}] =
             Notifications.list_native_push_tokens(user.id)
  end

  test "an iOS token defaults to the production APNs environment", %{conn: conn} do
    FakeNativePushSender.enable([:apns])

    response =
      conn
      |> post("/api/notifications/native-push-tokens", %{
        provider: "apns",
        platform: "ios",
        token: @apns_token
      })
      |> json_response(201)

    assert response["native_push_token"]["apns_environment"] == "production"
  end

  test "a provider that does not match the platform is refused", %{conn: conn} do
    FakeNativePushSender.enable([:fcm, :apns])

    conn
    |> post("/api/notifications/native-push-tokens", %{
      provider: "apns",
      platform: "android",
      token: @apns_token
    })
    |> json_response(422)
  end

  test "the token moves to whoever signs in on the install next", %{conn: conn, user: user} do
    FakeNativePushSender.enable([:fcm])
    params = %{provider: "fcm", platform: "android", token: @fcm_token}

    conn |> post("/api/notifications/native-push-tokens", params) |> json_response(201)

    other = user_fixture()

    build_conn()
    |> put_bearer_token(other)
    |> Plug.Conn.put_req_header("content-type", "application/json")
    |> post("/api/notifications/native-push-tokens", params)
    |> json_response(201)

    assert Notifications.list_native_push_tokens(user.id) == []
    assert [%{token: @fcm_token}] = Notifications.list_native_push_tokens(other.id)
  end

  test "unregistering stops push to the install", %{conn: conn, user: user} do
    FakeNativePushSender.enable([:fcm])

    conn
    |> post("/api/notifications/native-push-tokens", %{
      provider: "fcm",
      platform: "android",
      token: @fcm_token
    })
    |> json_response(201)

    assert %{"deleted" => true} =
             conn
             |> post("/api/notifications/native-push-tokens/unregister", %{token: @fcm_token})
             |> json_response(200)

    assert Notifications.list_native_push_tokens(user.id) == []

    assert %{"deleted" => false} =
             conn
             |> post("/api/notifications/native-push-tokens/unregister", %{token: @fcm_token})
             |> json_response(200)
  end

  test "registration needs a signed-in person" do
    FakeNativePushSender.enable([:fcm])

    build_conn()
    |> Plug.Conn.put_req_header("content-type", "application/json")
    |> post("/api/notifications/native-push-tokens", %{
      provider: "fcm",
      platform: "android",
      token: @fcm_token
    })
    |> json_response(401)
  end
end
