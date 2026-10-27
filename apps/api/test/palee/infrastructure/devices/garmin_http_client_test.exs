defmodule Palee.Infrastructure.Devices.GarminHttpClientTest do
  use ExUnit.Case, async: false

  alias Palee.Infrastructure.Devices.GarminHttpClient, as: Client
  alias Palee.Infrastructure.Security.{DataCipher, EncryptedBinary}

  setup do
    previous = Application.get_env(:palee, :garmin)
    on_exit(fn -> Application.put_env(:palee, :garmin, previous || []) end)
    :ok
  end

  defp configure(extra \\ []) do
    Application.put_env(
      :palee,
      :garmin,
      [
        client_id: "client-1",
        client_secret: "secret-1",
        redirect_uri: "https://palee.test/api/integrations/garmin/callback",
        req_options: [plug: {Req.Test, __MODULE__}, retry: false]
      ] ++ extra
    )
  end

  test "without credentials nothing is configured and every call says so" do
    Application.put_env(:palee, :garmin, client_id: nil, client_secret: "")
    refute Client.configured?()
    assert {:error, :garmin_not_configured} = Client.authorize_url(%{state: "s", challenge: "c"})
    assert {:error, :garmin_not_configured} = Client.refresh("r")
    assert {:error, :garmin_not_configured} = Client.verify_push(%{client_id: "x", token: nil})
  end

  test "the sign-in URL carries the PKCE challenge, state and redirect" do
    configure()
    assert Client.configured?()
    {:ok, url} = Client.authorize_url(%{state: "state-1", challenge: "challenge-1"})
    %URI{host: "connect.garmin.com", query: query} = URI.parse(url)

    assert %{
             "response_type" => "code",
             "client_id" => "client-1",
             "code_challenge" => "challenge-1",
             "code_challenge_method" => "S256",
             "state" => "state-1",
             "redirect_uri" => "https://palee.test/api/integrations/garmin/callback"
           } = URI.decode_query(query)
  end

  test "the code exchange sends the verifier and reads the tokens" do
    configure()

    Req.Test.stub(__MODULE__, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      form = URI.decode_query(body)
      assert form["grant_type"] == "authorization_code"
      assert form["code_verifier"] == "verifier-1"
      assert form["client_secret"] == "secret-1"

      Req.Test.json(conn, %{
        "access_token" => "a",
        "refresh_token" => "r",
        "expires_in" => 86_400,
        "refresh_token_expires_in" => 7_776_000,
        "scope" => "ACTIVITY_EXPORT HEALTH_EXPORT"
      })
    end)

    assert {:ok, %{access_token: "a", refresh_token: "r", expires_in: 86_400, scopes: scopes}} =
             Client.exchange_code(%{code: "code-1", verifier: "verifier-1"})

    assert scopes == ["ACTIVITY_EXPORT", "HEALTH_EXPORT"]
  end

  test "a refused refresh grant is told apart from an outage" do
    configure()

    Req.Test.stub(__MODULE__, fn conn ->
      conn |> Plug.Conn.put_status(400) |> Req.Test.json(%{"error" => "invalid_grant"})
    end)

    assert {:error, :garmin_invalid_grant} = Client.refresh("r")
  end

  test "user id, backfill and deregistration call Garmin's API with the bearer token" do
    configure()

    Req.Test.stub(__MODULE__, fn conn ->
      assert Plug.Conn.get_req_header(conn, "authorization") == ["Bearer t"]

      case {conn.method, conn.request_path} do
        {"GET", "/wellness-api/rest/user/id"} ->
          Req.Test.json(conn, %{"userId" => "g-1"})

        {"GET", "/wellness-api/rest/backfill/activities"} ->
          assert %{"summaryStartTimeInSeconds" => _, "summaryEndTimeInSeconds" => _} =
                   URI.decode_query(conn.query_string)

          conn |> Plug.Conn.put_status(409) |> Req.Test.json(%{})

        {"DELETE", "/wellness-api/rest/user/registration"} ->
          Plug.Conn.send_resp(conn, 204, "")
      end
    end)

    assert {:ok, "g-1"} = Client.user_id("t")
    now = DateTime.utc_now()
    assert :ok = Client.request_backfill("t", "activities", DateTime.add(now, -86_400), now)
    assert :ok = Client.deregister("t")
  end

  test "ping callbacks are fetched only from Garmin's API host" do
    configure()
    Req.Test.stub(__MODULE__, fn conn -> Req.Test.json(conn, [%{"summaryId" => "1"}]) end)

    assert {:ok, [%{"summaryId" => "1"}]} =
             Client.fetch("t", "https://apis.garmin.com/wellness-api/rest/activities?token=x")

    assert {:error, :invalid_callback_url} = Client.fetch("t", "https://evil.test/steal")
    assert {:error, :invalid_callback_url} = Client.fetch("t", "http://apis.garmin.com/x")
  end

  test "a push must name this app's client id, and the push token when one is set" do
    configure()
    assert :ok = Client.verify_push(%{client_id: "client-1", token: nil})
    assert {:error, :invalid_push} = Client.verify_push(%{client_id: "other", token: nil})
    assert {:error, :invalid_push} = Client.verify_push(%{client_id: nil, token: nil})

    configure(push_token: "push-secret")
    assert {:error, :invalid_push} = Client.verify_push(%{client_id: "client-1", token: nil})
    assert :ok = Client.verify_push(%{client_id: "client-1", token: "push-secret"})
  end

  test "secrets are encrypted at rest and a foreign value loads as nil" do
    cipher = DataCipher.encrypt("token-1")
    refute cipher =~ "token-1"
    refute DataCipher.encrypt("token-1") == cipher
    assert {:ok, "token-1"} = DataCipher.decrypt(cipher)

    {:ok, dumped} = EncryptedBinary.dump("token-2")
    assert {:ok, "token-2"} = EncryptedBinary.load(dumped)
    assert {:ok, nil} = EncryptedBinary.load("v2" <> :crypto.strong_rand_bytes(40))
  end
end
