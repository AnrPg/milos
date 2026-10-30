defmodule PaleeWeb.PlatformPushSettingsControllerTest do
  use PaleeWeb.ConnCase, async: false

  import Palee.TestFixtures

  alias Palee.Notifications
  alias Palee.Notifications.Domain.VapidKeys
  alias Palee.Notifications.PushKeyStore
  alias Palee.Organizations

  setup do
    vendor = user_fixture(%{nickname: "push_vendor"})
    {:ok, _vendor} = Organizations.grant_vendor(vendor.id)
    %{vendor: vendor}
  end

  defp auto_keys(_context) do
    Application.put_env(:palee, :web_push_auto_keys, true)
    on_exit(fn -> Application.put_env(:palee, :web_push_auto_keys, false) end)
    :ok
  end

  defp server_keys(keys) do
    Application.put_env(:palee, :web_push_server_keys, keys)
    on_exit(fn -> Application.delete_env(:palee, :web_push_server_keys) end)
  end

  defp subscribe(user) do
    {:ok, subscription, :created} =
      Notifications.save_push_subscription(user.id, %{
        "endpoint" => "https://push.example.test/#{System.unique_integer([:positive])}",
        "keys" => %{"p256dh" => "p256dh", "auth" => "auth"}
      })

    subscription
  end

  test "only the platform team reads or changes browser alerts", %{conn: conn} do
    admin = admin_fixture(%{nickname: "gym_owner"})

    for request <- [
          &get(&1, "/api/platform/push-settings"),
          &patch(&1, "/api/platform/push-settings", %{vapid_subject: "ops@palee.example"}),
          &post(&1, "/api/platform/push-settings/rotate")
        ] do
      assert %{"code" => "vendor_required"} =
               conn |> recycle() |> put_bearer_token(admin) |> request.() |> json_response(403)
    end
  end

  test "the device figures refuse anyone but a vendor, even inside the database", %{} do
    member = user_fixture()

    assert_raise Postgrex.Error, ~r/vendor required/, fn ->
      PushKeyStore.with_user_context(%{user_id: member.id}, &PushKeyStore.device_stats/0)
    end

    assert_raise Postgrex.Error, ~r/vendor required/, fn ->
      PushKeyStore.with_user_context(%{user_id: member.id}, &PushKeyStore.forget_all_devices/0)
    end
  end

  describe "with keys made by the server (ADR-277)" do
    setup :auto_keys

    test "the first use makes a pair, members' browsers get the public key and no key is shown",
         %{conn: conn, vendor: vendor} do
      status =
        conn
        |> put_bearer_token(vendor)
        |> get("/api/platform/push-settings")
        |> json_response(200)

      assert %{
               "enabled" => true,
               "source" => "palee",
               "vapid_subject" => "mailto:alerts@palee.app",
               "subject_source" => "default",
               "device_count" => 0,
               "last_sent_at" => nil
             } = status

      assert is_binary(status["keys_created_at"])
      refute Enum.any?(Map.keys(status), &(&1 =~ ~r/public|private/))

      config =
        conn
        |> recycle()
        |> put_bearer_token(vendor)
        |> get("/api/notifications/push-config")
        |> json_response(200)

      assert config["enabled"] == true

      assert VapidKeys.valid?(%{
               public_key: config["vapid_public_key"],
               private_key: PushKeyStore.get().vapid_private_key
             })
    end

    test "the private key is stored encrypted", %{} do
      assert Palee.Notifications.PushConfig.enabled?()

      %{rows: [[stored]]} =
        Palee.Repo.query!("SELECT vapid_private_key_encrypted FROM notification_push_settings")

      refute stored == PushKeyStore.get().vapid_private_key
      assert String.starts_with?(stored, "v2")
    end

    test "concurrent first uses keep one pair", %{} do
      keys =
        1..4
        |> Enum.map(fn _ ->
          Task.async(fn -> PushKeyStore.put_keys_if_missing(VapidKeys.generate()) end)
        end)
        |> Enum.map(&Task.await/1)
        |> Enum.map(& &1.vapid_public_key)
        |> Enum.uniq()

      assert length(keys) == 1
      assert %{num_rows: 1} = Palee.Repo.query!("SELECT 1 FROM notification_push_settings")
    end

    test "a vendor saves the contact; a plain email gets mailto:", %{conn: conn, vendor: vendor} do
      payload =
        conn
        |> put_bearer_token(vendor)
        |> patch("/api/platform/push-settings", %{vapid_subject: " ops@palee.example "})
        |> json_response(200)

      assert payload["vapid_subject"] == "mailto:ops@palee.example"
      assert payload["subject_source"] == "palee"

      assert %{"code" => "invalid_push_contact"} =
               conn
               |> recycle()
               |> put_bearer_token(vendor)
               |> patch("/api/platform/push-settings", %{vapid_subject: "not a contact"})
               |> json_response(422)
    end

    test "new keys replace the pair and forget every browser subscription", %{
      conn: conn,
      vendor: vendor
    } do
      before = Palee.Notifications.PushConfig.public_key()
      member = user_fixture()
      subscribe(member)
      subscribe(vendor)

      assert %{"device_count" => 2} =
               conn
               |> put_bearer_token(vendor)
               |> get("/api/platform/push-settings")
               |> json_response(200)

      assert %{"device_count" => 0, "enabled" => true} =
               conn
               |> recycle()
               |> put_bearer_token(vendor)
               |> post("/api/platform/push-settings/rotate")
               |> json_response(200)

      refute Palee.Notifications.PushConfig.public_key() == before
      assert Notifications.get_push_subscriptions(member.id) == []
    end
  end

  describe "with WEB_PUSH_* given to the server" do
    setup :auto_keys

    test "the server's keys win and cannot be replaced or overridden here", %{
      conn: conn,
      vendor: vendor
    } do
      server = VapidKeys.generate()

      server_keys(
        public_key: server.public_key,
        private_key: server.private_key,
        subject: "mailto:ops@palee.example"
      )

      assert %{
               "source" => "server",
               "subject_source" => "server",
               "vapid_subject" => "mailto:ops@palee.example"
             } =
               conn
               |> put_bearer_token(vendor)
               |> get("/api/platform/push-settings")
               |> json_response(200)

      assert Palee.Notifications.PushConfig.public_key() == server.public_key

      for request <- [
            &post(&1, "/api/platform/push-settings/rotate"),
            &patch(&1, "/api/platform/push-settings", %{vapid_subject: "x@palee.example"})
          ] do
        assert %{"code" => "push_managed_by_server"} =
                 conn |> recycle() |> put_bearer_token(vendor) |> request.() |> json_response(409)
      end
    end
  end

  test "with automatic keys off and nothing stored, browser alerts stay off", %{
    conn: conn,
    vendor: vendor
  } do
    assert %{"enabled" => false, "source" => "none"} =
             conn
             |> put_bearer_token(vendor)
             |> get("/api/platform/push-settings")
             |> json_response(200)
  end
end
