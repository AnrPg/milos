defmodule PaleeWeb.AdminFiscalRegistryControllerTest do
  @moduledoc """
  ADR-265 over HTTP: «Συμπλήρωση από το ΑΦΜ». The ΑΦΜ check digit comes
  first; the business's own AADE credentials are stored encrypted, never
  returned or journaled; the sandbox answers without them; production asks
  AADE's RgWsPublic2 (stubbed) and refused credentials mark the connection.
  """

  use PaleeWeb.ConnCase, async: false

  import Palee.TestFixtures

  alias Palee.{Organizations, Repo}

  setup %{conn: conn} do
    admin = admin_fixture(%{nickname: "reg_admin"})
    coach = user_fixture(%{nickname: "reg_coach"})

    {:ok, organization} =
      Organizations.create_organization(%{name: "Registry #{System.unique_integer([:positive])}"})

    for {user, role} <- [{admin, :owner}, {coach, :coach}] do
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
      owner: put_bearer_token(conn, admin),
      coach: put_bearer_token(conn, coach),
      base: "/api/org/#{organization.slug}/admin/fiscal",
      organization: organization
    }
  end

  defp put_json(conn, path, body) do
    conn
    |> recycle()
    |> put_req_header("content-type", "application/json")
    |> put(path, Jason.encode!(body))
  end

  defp get_json(conn, path), do: conn |> recycle() |> get(path)

  test "the check digit is verified before anything else", ctx do
    assert %{"code" => "invalid_tax_id"} =
             ctx.owner
             |> get_json("#{ctx.base}/registry/businesses/090000046")
             |> json_response(422)

    assert %{"code" => "registry_not_connected"} =
             ctx.owner
             |> get_json("#{ctx.base}/registry/businesses/090000045")
             |> json_response(409)
  end

  test "the sandbox answers without credentials", ctx do
    assert %{"connection" => nil} =
             ctx.owner |> get_json("#{ctx.base}/registry-connection") |> json_response(200)

    assert %{"connection" => %{"environment" => "sandbox", "has_password" => false}} =
             ctx.owner
             |> put_json("#{ctx.base}/registry-connection", %{environment: "sandbox"})
             |> json_response(200)

    assert %{
             "business" => %{
               "tax_id" => "090000045",
               "legal_name" => "ΔΟΚΙΜΑΣΤΙΚΗ ΑΘΛΗΤΙΚΗ Ι.Κ.Ε.",
               "activity_code" => "93130000",
               "active" => true
             }
           } =
             ctx.owner
             |> get_json("#{ctx.base}/registry/businesses/09%200000%20045")
             |> json_response(200)

    assert %{"code" => "registry_not_found"} =
             ctx.owner
             |> get_json("#{ctx.base}/registry/businesses/100060000")
             |> json_response(404)

    # Coaches cannot look up or connect.
    assert ctx.coach
           |> get_json("#{ctx.base}/registry/businesses/090000045")
           |> json_response(403)
  end

  test "production credentials are stored encrypted and never returned", ctx do
    assert %{"code" => "validation_failed", "errors" => %{"password" => ["required"]}} =
             ctx.owner
             |> put_json("#{ctx.base}/registry-connection", %{
               environment: "production",
               username: "BOXUSER"
             })
             |> json_response(422)

    body =
      ctx.owner
      |> put_json("#{ctx.base}/registry-connection", %{
        environment: "production",
        username: "BOXUSER",
        password: "very-secret-pw"
      })
      |> json_response(200)

    assert %{"connection" => %{"has_password" => true, "user_id" => "BOXUSER"}} = body
    refute Jason.encode!(body) =~ "very-secret-pw"

    %{rows: [[stored]]} =
      Repo.query!(
        "SELECT subscription_key FROM fiscal_authority_connections WHERE organization_id = $1 AND authority = 'gr_registry'",
        [Ecto.UUID.dump!(ctx.organization.id)]
      )

    refute stored =~ "very-secret-pw"

    %{rows: journal} =
      Repo.query!(
        "SELECT payload::text FROM fiscal_journal_entries WHERE organization_id = $1 AND event_type = 'registry_connection_saved'",
        [Ecto.UUID.dump!(ctx.organization.id)]
      )

    assert [[payload]] = journal
    refute payload =~ "very-secret-pw"

    # AADE refuses the credentials: the connection is marked and says so.
    Req.Test.stub(Palee.FiscalHttp, fn conn ->
      Plug.Conn.send_resp(
        conn,
        200,
        "<env:Envelope xmlns:env=\"http://www.w3.org/2003/05/soap-envelope\"><env:Body><error_rec>" <>
          "<error_code>RG_WS_PUBLIC_TOKEN_USERNAME_NOT_AUTHENTICATED</error_code></error_rec>" <>
          "</env:Body></env:Envelope>"
      )
    end)

    assert %{"code" => "registry_credentials_rejected"} =
             ctx.owner
             |> get_json("#{ctx.base}/registry/businesses/090000045")
             |> json_response(409)

    assert %{"connection" => %{"status" => "invalid"}} =
             ctx.owner |> get_json("#{ctx.base}/registry-connection") |> json_response(200)

    # New credentials make it active again.
    assert %{"connection" => %{"status" => "active"}} =
             ctx.owner
             |> put_json("#{ctx.base}/registry-connection", %{
               environment: "production",
               password: "new-secret-pw"
             })
             |> json_response(200)
  end
end
