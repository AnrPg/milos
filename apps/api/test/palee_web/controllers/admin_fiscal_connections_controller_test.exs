defmodule PaleeWeb.AdminFiscalConnectionsControllerTest do
  @moduledoc """
  ADR-273 over HTTP: the «Συνδέσεις» card lists only the connections the
  box's country asks for; every save is checked right away and
  «Δοκιμή σύνδεσης» checks on demand (a refusal marks the connection
  invalid with a stable code, an unreachable provider changes nothing);
  the Palee team can manage a box's connections from the vendor console,
  audited and without any secret.
  """

  use PaleeWeb.ConnCase, async: false

  import Palee.TestFixtures

  alias Palee.{Organizations, Repo}

  @identity %{
    "legal_name" => "CrossFit Αθήνα ΙΚΕ",
    "country_code" => "GR",
    "tax_id" => "090000045",
    "tax_office" => "Α' Αθηνών",
    "street" => "Ερμού",
    "postal_code" => "10563",
    "city" => "Αθήνα"
  }

  setup %{conn: conn} do
    owner = admin_fixture(%{nickname: "conn_owner"})
    coach = user_fixture(%{nickname: "conn_coach"})
    vendor = user_fixture(%{nickname: "conn_vendor"})
    {:ok, _} = Organizations.grant_vendor(vendor.id)

    {:ok, organization} =
      Organizations.create_organization(%{
        name: "Connections #{System.unique_integer([:positive])}"
      })

    for {user, role} <- [{owner, :owner}, {coach, :coach}] do
      {:ok, _} =
        Organizations.add_membership(%{
          organization_id: organization.id,
          user_id: user.id,
          role: role,
          status: :active,
          joined_at: DateTime.utc_now()
        })
    end

    %{
      owner: put_bearer_token(conn, owner),
      coach: put_bearer_token(conn, coach),
      vendor: put_bearer_token(conn, vendor),
      admin: "/api/org/#{organization.slug}/admin/fiscal",
      platform: "/api/platform/organizations/#{organization.id}/fiscal-connections",
      organization: organization
    }
  end

  defp send_json(conn, method, path, body \\ %{}) do
    conn
    |> recycle()
    |> put_req_header("content-type", "application/json")
    |> dispatch(@endpoint, method, path, Jason.encode!(body))
  end

  defp get_json(conn, path), do: conn |> recycle() |> get(path)

  defp greek_box(ctx) do
    ctx.owner |> send_json(:put, "#{ctx.admin}/identity", @identity) |> json_response(200)
  end

  # The 30-second guard between two checks is not what these tests are about.
  defp age_check(ctx, table) do
    Repo.query!(
      "UPDATE #{table} SET checked_at = now() - interval '1 hour' WHERE organization_id = $1",
      [Ecto.UUID.dump!(ctx.organization.id)]
    )
  end

  test "before a country there is nothing to connect", ctx do
    assert %{"country" => nil, "kinds" => [], "managed_by" => "owner"} =
             ctx.owner |> get_json("#{ctx.admin}/connections") |> json_response(200)

    assert ctx.coach |> get_json("#{ctx.admin}/connections") |> json_response(403)
  end

  test "myDATA: the save is checked, a refusal marks it, «Δοκιμή σύνδεσης» restores it", ctx do
    greek_box(ctx)

    assert %{
             "country" => "GR",
             "kinds" => ["mydata", "registry"],
             "connections" => %{"mydata" => nil, "registry" => nil}
           } = ctx.owner |> get_json("#{ctx.admin}/connections") |> json_response(200)

    assert %{"code" => "connection_not_found"} =
             ctx.owner
             |> send_json(:post, "#{ctx.admin}/connections/mydata/check")
             |> json_response(404)

    # AADE refuses the key: saved, but invalid with a stable code.
    Req.Test.stub(Palee.FiscalHttp, fn conn -> Plug.Conn.send_resp(conn, 401, "denied") end)

    body =
      ctx.owner
      |> send_json(:put, "#{ctx.admin}/authority-connection", %{
        "environment" => "test",
        "user_id" => "boxuser",
        "subscription_key" => "very-secret-key"
      })
      |> json_response(200)

    assert %{
             "check" => %{"result" => "invalid", "error_code" => "credentials_rejected"},
             "connection" => %{"status" => "invalid", "error_code" => "credentials_rejected"}
           } = body

    refute Jason.encode!(body) =~ "very-secret-key"
    refute Map.has_key?(body["connection"], "last_error")

    # A second check right away is refused.
    assert %{"code" => "check_too_soon"} =
             ctx.owner
             |> send_json(:post, "#{ctx.admin}/connections/mydata/check")
             |> json_response(429)

    # AADE accepts it now: the check makes it active again.
    age_check(ctx, "fiscal_authority_connections")

    Req.Test.stub(Palee.FiscalHttp, fn conn ->
      Plug.Conn.send_resp(conn, 200, "<RequestedDoc/>")
    end)

    assert %{
             "check" => %{"result" => "ok", "error_code" => nil},
             "connection" => %{"status" => "active", "error_code" => nil, "checked_at" => checked}
           } =
             ctx.owner
             |> send_json(:post, "#{ctx.admin}/connections/mydata/check")
             |> json_response(200)

    assert is_binary(checked)

    # AADE cannot be reached: nothing changes.
    age_check(ctx, "fiscal_authority_connections")
    Req.Test.stub(Palee.FiscalHttp, fn conn -> Plug.Conn.send_resp(conn, 503, "busy") end)

    assert %{
             "check" => %{"result" => "unreachable", "error_code" => "unreachable"},
             "connection" => %{"status" => "active"}
           } =
             ctx.owner
             |> send_json(:post, "#{ctx.admin}/connections/mydata/check")
             |> json_response(200)

    overview = ctx.owner |> get_json("#{ctx.admin}/connections") |> json_response(200)

    assert %{
             "mydata" => %{
               "status" => "active",
               "has_subscription_key" => true,
               "updated_by_name" => "conn_owner",
               "updated_by_platform" => false
             }
           } = overview["connections"]

    refute Jason.encode!(overview) =~ "very-secret-key"

    # Coaches cannot check.
    assert ctx.coach
           |> send_json(:post, "#{ctx.admin}/connections/mydata/check")
           |> json_response(403)
  end

  test "registry: the check looks up the business's own ΑΦΜ, at most every 10 minutes", ctx do
    greek_box(ctx)

    assert %{
             "check" => %{
               "result" => "ok",
               "detail" => %{"tax_id" => "090000045", "legal_name" => legal_name}
             },
             "connection" => %{"status" => "active", "username" => nil}
           } =
             ctx.owner
             |> send_json(:put, "#{ctx.admin}/registry-connection", %{"environment" => "sandbox"})
             |> json_response(200)

    assert is_binary(legal_name)

    # One look-up of the business's quota: not again for 10 minutes.
    Repo.query!(
      "UPDATE fiscal_authority_connections SET checked_at = now() - interval '5 minutes' WHERE organization_id = $1",
      [Ecto.UUID.dump!(ctx.organization.id)]
    )

    assert %{"code" => "check_too_soon"} =
             ctx.owner
             |> send_json(:post, "#{ctx.admin}/connections/registry/check")
             |> json_response(429)
  end

  test "the Palee team manages a box's connections, audited and without secrets", ctx do
    greek_box(ctx)

    # Only vendors reach the console.
    assert %{"code" => "vendor_required"} =
             ctx.owner |> get_json(ctx.platform) |> json_response(403)

    assert %{"managed_by" => "palee", "kinds" => ["mydata", "registry"]} =
             ctx.vendor
             |> send_json(:put, "#{ctx.platform}/managed-by", %{"managed_by" => "palee"})
             |> json_response(200)

    # The owner sees who manages them and cannot save.
    assert %{"managed_by" => "palee"} =
             ctx.owner |> get_json("#{ctx.admin}/connections") |> json_response(200)

    assert %{"code" => "fiscal_connections_managed_by_palee"} =
             ctx.owner
             |> send_json(:put, "#{ctx.admin}/authority-connection", %{"environment" => "sandbox"})
             |> json_response(403)

    # The Palee team fills it in.
    Req.Test.stub(Palee.FiscalHttp, fn conn ->
      Plug.Conn.send_resp(conn, 200, "<RequestedDoc/>")
    end)

    body =
      ctx.vendor
      |> send_json(:put, "#{ctx.platform}/mydata", %{
        "environment" => "test",
        "user_id" => "boxuser",
        "subscription_key" => "palee-secret-key"
      })
      |> json_response(200)

    assert %{
             "check" => %{"result" => "ok"},
             "connection" => %{"status" => "active", "updated_by_platform" => true}
           } = body

    refute Jason.encode!(body) =~ "palee-secret-key"

    assert %{
             "connections" => %{
               "mydata" => %{"updated_by_platform" => true, "updated_by_name" => nil}
             }
           } =
             ctx.owner |> get_json("#{ctx.admin}/connections") |> json_response(200)

    # The owner can still run «Δοκιμή σύνδεσης».
    age_check(ctx, "fiscal_authority_connections")

    assert %{"check" => %{"result" => "ok"}} =
             ctx.owner
             |> send_json(:post, "#{ctx.admin}/connections/mydata/check")
             |> json_response(200)

    age_check(ctx, "fiscal_authority_connections")

    assert %{"check" => %{"result" => "ok"}} =
             ctx.vendor |> send_json(:post, "#{ctx.platform}/mydata/check") |> json_response(200)

    # The vendors' audit log and the fiscal journal say who, never the secret.
    %{rows: events} =
      Repo.query!(
        "SELECT event, metadata::text FROM organization_provisioning_events WHERE organization_id = $1 ORDER BY inserted_at",
        [Ecto.UUID.dump!(ctx.organization.id)]
      )

    assert ["fiscal_connections_manager_changed", "fiscal_connection_saved"] ==
             events |> Enum.map(&hd/1) |> Enum.filter(&String.starts_with?(&1, "fiscal_"))

    refute inspect(events) =~ "palee-secret-key"

    %{rows: [[payload]]} =
      Repo.query!(
        "SELECT payload::text FROM fiscal_journal_entries WHERE organization_id = $1 AND event_type = 'authority_connection_saved'",
        [Ecto.UUID.dump!(ctx.organization.id)]
      )

    assert payload =~ "by_platform"
    refute payload =~ "palee-secret-key"

    # Back to the owner.
    assert %{"managed_by" => "owner"} =
             ctx.vendor
             |> send_json(:put, "#{ctx.platform}/managed-by", %{"managed_by" => "owner"})
             |> json_response(200)

    assert %{"check" => %{"result" => "ok"}} =
             ctx.owner
             |> send_json(:put, "#{ctx.admin}/authority-connection", %{"environment" => "sandbox"})
             |> json_response(200)
  end
end
