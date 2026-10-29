defmodule PaleeWeb.PaymentConnectControllerTest do
  @moduledoc """
  ADR-261: one-button connection of a business's own Stripe account
  through Palee's Stripe Connect platform, against stubbed Stripe answers.
  """
  use PaleeWeb.ConnCase, async: false

  alias Palee.{Organizations, Payments}

  import Palee.TestFixtures

  setup do
    admin = admin_fixture(%{nickname: "connect_admin"})
    member = user_fixture(%{role: :member, nickname: "connect_member"})

    {:ok, organization} =
      Organizations.create_organization(%{
        name: "Connect Tenant #{System.unique_integer([:positive])}"
      })

    for {user, role} <- [{admin, :owner}, {member, :member}] do
      {:ok, _} =
        Organizations.add_membership(%{
          organization_id: organization.id,
          user_id: user.id,
          role: role,
          status: :active,
          joined_at: DateTime.utc_now()
        })
    end

    {:ok, context} = Organizations.resolve_tenant_context(admin, organization.slug)
    %{admin: admin, member: member, organization: organization, context: context}
  end

  defp admin_path(ctx, path), do: "/api/org/#{ctx.organization.slug}/admin#{path}"

  defp start(conn, ctx, user \\ nil) do
    conn
    |> put_bearer_token(user || ctx.admin)
    |> post(admin_path(ctx, "/payments/connect"), %{provider: "stripe", environment: "test"})
  end

  defp state_of(url), do: URI.decode_query(URI.parse(url).query)["state"]

  defp stub_stripe(account \\ "acct_1Palee") do
    Req.Test.stub(Palee.PaymentsHttp, fn conn ->
      case {conn.host, conn.request_path} do
        {"connect.stripe.com", "/oauth/token"} ->
          {:ok, body, conn} = Plug.Conn.read_body(conn)
          params = URI.decode_query(body)
          assert params["grant_type"] == "authorization_code"
          assert Plug.Conn.get_req_header(conn, "authorization") == ["Bearer sk_test_platform"]

          if params["code"] == "ac_good",
            do:
              Req.Test.json(conn, %{
                "stripe_user_id" => account,
                "livemode" => false,
                "scope" => "read_write"
              }),
            else:
              conn
              |> Plug.Conn.put_status(400)
              |> Req.Test.json(%{"error" => "invalid_grant"})

        {"api.stripe.com", "/v1/balance"} ->
          assert Plug.Conn.get_req_header(conn, "stripe-account") == [account]
          assert Plug.Conn.get_req_header(conn, "authorization") == ["Bearer sk_test_platform"]
          Req.Test.json(conn, %{"object" => "balance"})

        {"connect.stripe.com", "/oauth/deauthorize"} ->
          {:ok, body, conn} = Plug.Conn.read_body(conn)
          assert URI.decode_query(body)["stripe_user_id"] == account
          Req.Test.json(conn, %{"stripe_user_id" => account})
      end
    end)
  end

  test "the owner connects Stripe with one button", %{conn: conn} = ctx do
    status =
      conn
      |> put_bearer_token(ctx.admin)
      |> get(admin_path(ctx, "/payments/account"))
      |> json_response(200)

    assert status["connect_providers"] == %{"test" => ["stripe"], "live" => []}

    url = conn |> start(ctx) |> json_response(200) |> Map.fetch!("url")
    assert url =~ "https://connect.stripe.com/oauth/authorize?"
    query = URI.decode_query(URI.parse(url).query)
    assert query["client_id"] == "ca_test_platform"
    assert query["scope"] == "read_write"
    assert query["redirect_uri"] =~ "/api/payments/connect/callback"

    stub_stripe()

    back =
      build_conn()
      |> get("/api/payments/connect/callback", %{code: "ac_good", state: state_of(url)})

    assert redirected_to(back) == "/admin/settings?tab=payments&connect=ok"

    account = Payments.account(ctx.context)
    assert account.provider == "stripe"
    assert account.connection == "platform"
    assert account.credentials_set == ["connected_account"]
    assert Payments.available?(ctx.context)

    # Disconnecting removes Palee's access and stops online payments.
    disconnected =
      conn
      |> put_bearer_token(ctx.admin)
      |> delete(admin_path(ctx, "/payments/account"))
      |> json_response(200)

    assert disconnected["account"]["status"] == "disabled"
    refute Payments.available?(ctx.context)
  end

  test "a forged or reused state, a refusal and a bad code change nothing", %{conn: conn} = ctx do
    url = conn |> start(ctx) |> json_response(200) |> Map.fetch!("url")
    stub_stripe()

    callback = fn params ->
      build_conn() |> get("/api/payments/connect/callback", params) |> redirected_to()
    end

    assert callback.(%{code: "ac_good", state: "forged"}) =~ "connect=connect_state_invalid"
    assert callback.(%{error: "access_denied", state: state_of(url)}) =~ "connect=access_denied"
    assert callback.(%{code: "ac_bad", state: state_of(url)}) =~ "connect=invalid_grant"
    assert Payments.account(ctx.context) == nil
  end

  test "only staff who manage billing can start, and live needs a platform",
       %{conn: conn} = ctx do
    conn |> start(ctx, ctx.member) |> json_response(403)

    conn
    |> put_bearer_token(ctx.admin)
    |> post(admin_path(ctx, "/payments/connect"), %{provider: "stripe", environment: "live"})
    |> json_response(409)
    |> then(&assert(&1["code"] == "connect_not_available"))

    conn
    |> put_bearer_token(ctx.admin)
    |> post(admin_path(ctx, "/payments/connect"), %{provider: "viva", environment: "test"})
    |> json_response(409)
  end
end
