defmodule MilosTraining.Infrastructure.Notifications.NativePushSendersTest do
  # ADR-171: the FCM HTTP v1 and APNs adapters against fake providers.
  use ExUnit.Case, async: false

  alias MilosTraining.Infrastructure.Notifications.{ApnsSender, FcmSender, NativePushTokenCache}

  @message %{title: "Νέο μήνυμα", body: "Γεια", url: "/messages", notification_id: "n-1"}

  setup do
    previous = Application.get_env(:milos_training, :native_push)
    NativePushTokenCache.forget({:fcm, "push@milos-test.iam.gserviceaccount.com"})
    NativePushTokenCache.forget({:apns, "TEAM123456", "KEY1234567"})

    on_exit(fn ->
      Application.put_env(:milos_training, :native_push, previous || [])
    end)

    :ok
  end

  defp pem(jwk) do
    {_meta, pem} = JOSE.JWK.to_pem(jwk)
    pem
  end

  defp configure(section, values) do
    current = Application.get_env(:milos_training, :native_push, [])
    Application.put_env(:milos_training, :native_push, Keyword.put(current, section, values))
  end

  defp configure_fcm do
    service_account =
      Jason.encode!(%{
        "type" => "service_account",
        "project_id" => "milos-test",
        "client_email" => "push@milos-test.iam.gserviceaccount.com",
        "private_key" => pem(JOSE.JWK.generate_key({:rsa, 2048}))
      })

    configure(:fcm,
      service_account: service_account,
      req_options: [plug: {Req.Test, FcmSender}]
    )
  end

  defp configure_apns do
    key = JOSE.JWK.generate_key({:ec, "P-256"})

    configure(:apns,
      team_id: "TEAM123456",
      key_id: "KEY1234567",
      private_key: pem(key),
      topic: "app.milos.member",
      req_options: [plug: {Req.Test, ApnsSender}]
    )

    key
  end

  describe "without credentials" do
    test "both providers are off and say so" do
      Application.put_env(:milos_training, :native_push, fcm: [], apns: [team_id: "T"])
      refute FcmSender.configured?()
      refute ApnsSender.configured?()
      assert FcmSender.send_push(%{token: "t"}, @message) == {:error, :push_not_configured}
      assert ApnsSender.send_push(%{token: "t"}, @message) == {:error, :push_not_configured}
    end

    test "an unreadable key is not a configuration" do
      configure(:apns, team_id: "T", key_id: "K", private_key: "/nonexistent/key.p8")
      refute ApnsSender.configured?()
    end
  end

  describe "FCM" do
    test "gets an access token once and posts the message to the project" do
      configure_fcm()
      assert FcmSender.configured?()
      parent = self()

      Req.Test.stub(FcmSender, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)

        case conn.request_path do
          "/token" ->
            form = URI.decode_query(body)
            send(parent, {:oauth, form})
            Req.Test.json(conn, %{"access_token" => "access-1", "expires_in" => 3599})

          "/v1/projects/milos-test/messages:send" ->
            send(
              parent,
              {:send, Plug.Conn.get_req_header(conn, "authorization"), Jason.decode!(body)}
            )

            Req.Test.json(conn, %{"name" => "projects/milos-test/messages/1"})
        end
      end)

      assert FcmSender.send_push(%{token: "device-1"}, @message) == :ok
      assert FcmSender.send_push(%{token: "device-2"}, @message) == :ok

      assert_received {:oauth,
                       %{
                         "grant_type" => "urn:ietf:params:oauth:grant-type:jwt-bearer",
                         "assertion" => assertion
                       }}

      [_header, claims, _signature] = String.split(assertion, ".")
      claims = claims |> Base.url_decode64!(padding: false) |> Jason.decode!()
      assert claims["scope"] == "https://www.googleapis.com/auth/firebase.messaging"
      assert claims["iss"] == "push@milos-test.iam.gserviceaccount.com"
      refute_received {:oauth, _}

      assert_received {:send, ["Bearer access-1"],
                       %{"message" => %{"token" => "device-1", "data" => %{"url" => "/messages"}}}}

      assert_received {:send, ["Bearer access-1"], %{"message" => %{"token" => "device-2"}}}
    end

    test "an unregistered token is reported as gone" do
      configure_fcm()

      Req.Test.stub(FcmSender, fn conn ->
        case conn.request_path do
          "/token" ->
            Req.Test.json(conn, %{"access_token" => "access-1", "expires_in" => 3599})

          _send ->
            conn
            |> Plug.Conn.put_status(404)
            |> Req.Test.json(%{
              "error" => %{
                "status" => "NOT_FOUND",
                "details" => [%{"errorCode" => "UNREGISTERED"}]
              }
            })
        end
      end)

      assert FcmSender.send_push(%{token: "gone"}, @message) == {:error, :expired}
    end

    test "a refused OAuth grant is an error, not a send" do
      configure_fcm()

      Req.Test.stub(FcmSender, fn conn ->
        conn |> Plug.Conn.put_status(400) |> Req.Test.json(%{"error" => "invalid_grant"})
      end)

      assert FcmSender.send_push(%{token: "device"}, @message) == {:error, {:fcm_oauth, 400}}
    end
  end

  describe "APNs" do
    test "posts the alert with a signed provider token to the token's environment" do
      key = configure_apns()
      assert ApnsSender.configured?()
      parent = self()

      Req.Test.stub(ApnsSender, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        send(parent, {:apns, conn.host, conn.request_path, conn.req_headers, Jason.decode!(body)})
        Plug.Conn.send_resp(conn, 200, "")
      end)

      assert ApnsSender.send_push(%{token: "abc123", apns_environment: "sandbox"}, @message) ==
               :ok

      assert ApnsSender.send_push(%{token: "def456", apns_environment: "production"}, @message) ==
               :ok

      assert_received {:apns, "api.sandbox.push.apple.com", "/3/device/abc123", headers, payload}
      assert_received {:apns, "api.push.apple.com", "/3/device/def456", second_headers, _payload}

      assert payload["aps"]["alert"]["title"] == "Νέο μήνυμα"
      assert payload["url"] == "/messages"
      headers = Map.new(headers)
      assert headers["apns-topic"] == "app.milos.member"
      assert headers["apns-push-type"] == "alert"

      "bearer " <> jwt = headers["authorization"]
      assert Map.new(second_headers)["authorization"] == headers["authorization"]

      public = JOSE.JWK.to_public(key)
      assert {true, claims, jws} = JOSE.JWT.verify_strict(public, ["ES256"], jwt)
      assert claims.fields["iss"] == "TEAM123456"
      assert jws.fields["kid"] == "KEY1234567"
    end

    test "a token Apple no longer knows is reported as gone" do
      configure_apns()

      Req.Test.stub(ApnsSender, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(410, Jason.encode!(%{"reason" => "Unregistered"}))
      end)

      assert ApnsSender.send_push(%{token: "gone"}, @message) == {:error, :expired}
    end

    test "other refusals are provider errors" do
      configure_apns()

      Req.Test.stub(ApnsSender, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(429, Jason.encode!(%{"reason" => "TooManyRequests"}))
      end)

      assert {:error, {:http_error, 429, %{"reason" => "TooManyRequests"}}} =
               ApnsSender.send_push(%{token: "busy"}, @message)
    end
  end
end
