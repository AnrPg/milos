defmodule PaleeWeb.PlatformPushSettingsControllerTest do
  use PaleeWeb.ConnCase, async: false

  import Palee.TestFixtures

  alias Palee.Organizations

  setup do
    vendor = user_fixture(%{nickname: "push_vendor"})
    {:ok, _vendor} = Organizations.grant_vendor(vendor.id)
    %{vendor: vendor}
  end

  test "only the platform team reads or edits the push keys", %{conn: conn} do
    admin = admin_fixture(%{nickname: "gym_owner"})

    for request <- [
          &get(&1, "/api/platform/push-settings"),
          &patch(&1, "/api/platform/push-settings", %{vapid_public_key: "x"})
        ] do
      assert %{"code" => "vendor_required"} =
               conn |> recycle() |> put_bearer_token(admin) |> request.() |> json_response(403)
    end
  end

  test "a vendor saves the keys and members' browsers get the public key", %{
    conn: conn,
    vendor: vendor
  } do
    assert %{"enabled" => false, "vapid_private_key_configured" => false} =
             conn
             |> put_bearer_token(vendor)
             |> get("/api/platform/push-settings")
             |> json_response(200)

    payload =
      conn
      |> recycle()
      |> put_bearer_token(vendor)
      |> patch("/api/platform/push-settings", %{
        vapid_public_key: "public-key",
        vapid_private_key: "private-key",
        vapid_subject: "mailto:alerts@palee.example"
      })
      |> json_response(200)

    assert payload["enabled"] == true
    assert payload["vapid_public_key"] == "public-key"
    assert payload["vapid_private_key_configured"] == true
    refute Map.has_key?(payload, "vapid_private_key")

    assert %{"enabled" => true, "vapid_public_key" => "public-key"} =
             conn
             |> recycle()
             |> put_bearer_token(vendor)
             |> get("/api/notifications/push-config")
             |> json_response(200)
  end

  test "leaving the private key out keeps the saved one", %{conn: conn, vendor: vendor} do
    {:ok, _} =
      Palee.Notifications.update_push_settings(%{
        vapid_public_key: "public-key",
        vapid_private_key: "private-key",
        vapid_subject: "mailto:alerts@palee.example"
      })

    payload =
      conn
      |> put_bearer_token(vendor)
      |> patch("/api/platform/push-settings", %{vapid_subject: "mailto:ops@palee.example"})
      |> json_response(200)

    assert payload["vapid_subject"] == "mailto:ops@palee.example"
    assert payload["vapid_private_key_configured"] == true
  end
end
