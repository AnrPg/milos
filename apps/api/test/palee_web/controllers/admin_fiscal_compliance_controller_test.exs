defmodule PaleeWeb.AdminFiscalComplianceControllerTest do
  @moduledoc """
  ADR-250 and ADR-251 over HTTP: owners connect Peppol and the till's
  security device (keys and secrets are never returned), staff with
  finance reports see submissions and signatures with what a receipt
  prints, owners retry and ask for an RKSV null receipt; front desk (by
  default) and coaches cannot. The Peppol webhook needs the secret URL.
  """

  use PaleeWeb.ConnCase, async: false

  import Palee.TestFixtures

  alias Palee.{Fiscal, Organizations, Repo}

  setup %{conn: conn} do
    {:ok, organization} = Organizations.ensure_legacy_organization_for_migration()
    Repo.query!("SELECT set_config($1, $2, false)", ["app.organization_id", organization.id])

    staff = fn role ->
      user = if role == :owner, do: admin_fixture(), else: user_fixture()
      {:ok, _} = Organizations.ensure_legacy_membership_for_migration(user, role)
      {user, put_bearer_token(conn, user)}
    end

    {owner_user, owner} = staff.(:owner)
    {_accountant_user, accountant} = staff.(:accountant)
    {_desk_user, desk} = staff.(:front_desk)
    {_coach_user, coach} = staff.(:coach)

    {:ok, context} =
      Organizations.resolve_tenant_context(owner_user, Organizations.legacy_organization_slug())

    %{
      conn: conn,
      organization: organization,
      context: context,
      owner_user: owner_user,
      owner: owner,
      accountant: accountant,
      desk: desk,
      coach: coach,
      admin: "/api/org/#{Organizations.legacy_organization_slug()}/admin"
    }
  end

  defp send_json(conn, method, path, body) do
    conn
    |> recycle()
    |> put_req_header("content-type", "application/json")
    |> dispatch(@endpoint, method, path, Jason.encode!(body))
  end

  defp get_json(conn, path), do: conn |> recycle() |> get(path)

  defp issue(ctx, attrs) do
    now = DateTime.utc_now()

    {:ok, document, :issued} =
      Fiscal.issue(
        ctx.context,
        Map.merge(
          %{
            issue_date: Organizations.local_date(ctx.context, now),
            lines: [%{description: "Abonnement", quantity: 1, unit_price_cents: 6000}]
          },
          attrs
        ),
        ctx.owner_user.id,
        now
      )

    document
  end

  describe "Peppol" do
    setup ctx do
      ctx.owner
      |> send_json(:put, "#{ctx.admin}/fiscal/identity", %{
        "legal_name" => "Box Bruxelles SRL",
        "country_code" => "BE",
        "tax_id" => "0403170701",
        "vat_number" => "BE0403170701",
        "street" => "Rue de la Loi",
        "building_number" => "16",
        "postal_code" => "1000",
        "city" => "Bruxelles"
      })
      |> json_response(200)

      :ok
    end

    test "connect, list, show, retry and the webhook", ctx do
      path = "#{ctx.admin}/fiscal/peppol-connection"

      assert %{"connection" => nil, "environments" => environments} =
               ctx.accountant |> get_json(path) |> json_response(200)

      assert "sandbox" in environments

      assert %{"errors" => errors} =
               ctx.owner
               |> send_json(:put, path, %{"environment" => "production"})
               |> json_response(422)

      assert Map.keys(errors) |> Enum.sort() == ["api_key", "api_secret", "legal_entity_id"]

      assert %{"connection" => connection} =
               ctx.owner
               |> send_json(:put, path, %{
                 "environment" => "test",
                 "legal_entity_id" => "12345",
                 "api_key" => "fk-secret-key",
                 "api_secret" => "fk-secret-value"
               })
               |> json_response(200)

      assert %{
               "peppol_id" => "0208:0403170701",
               "provider" => "fiskaly",
               "has_api_key" => true,
               "has_api_secret" => true,
               "credentials_source" => "own",
               "webhook_url" => url
             } = connection

      refute inspect(connection) =~ "fk-secret"
      refute ctx.accountant |> get_json(path) |> json_response(200) |> inspect() =~ "fk-secret"

      refute ctx.accountant |> get_json(path) |> json_response(200) |> inspect() =~
               "/api/webhooks"

      # Back to the sandbox for the delivery itself.
      ctx.owner |> send_json(:put, path, %{"environment" => "sandbox"}) |> json_response(200)

      document =
        issue(ctx, %{
          kind: "invoice",
          idempotency_key: "inv-1",
          payment_method: "bank_transfer",
          buyer: %{
            name: "Entreprise Cliente SA",
            vat_number: "BE0202239951",
            street: "Avenue Louise",
            postal_code: "1050",
            city: "Ixelles",
            country_code: "BE"
          }
        })

      Palee.Application.Fiscal.FiscalEInvoicing.transmit(ctx.context)

      assert %{"document" => %{"einvoice" => %{"status" => "submitted"}}} =
               ctx.accountant
               |> get_json("#{ctx.admin}/fiscal/documents/#{document.id}")
               |> json_response(200)

      assert %{"total" => 1, "submissions" => [row]} =
               ctx.accountant |> get_json("#{ctx.admin}/fiscal/einvoices") |> json_response(200)

      refute Map.has_key?(row, "organization_id")

      assert %{"submission" => %{"attempts_log" => [_ | _]}} =
               ctx.accountant
               |> get_json("#{ctx.admin}/fiscal/einvoices/#{row["id"]}")
               |> json_response(200)

      retry = "#{ctx.admin}/fiscal/documents/#{document.id}/einvoice/retry"

      assert %{"code" => "not_retryable"} =
               ctx.owner |> send_json(:post, retry, %{}) |> json_response(409)

      assert ctx.desk |> send_json(:post, retry, %{}) |> json_response(403)
      assert ctx.coach |> get_json("#{ctx.admin}/fiscal/einvoices") |> json_response(403)

      # The webhook: a wrong token is not found; the right one is a hint.
      %URI{path: webhook} = URI.parse(url)

      assert ctx.conn
             |> send_json(:post, "/api/webhooks/peppol/#{ctx.organization.id}/wrong", %{})
             |> json_response(404)

      assert %{"ok" => true} =
               ctx.conn
               |> send_json(:post, webhook, %{"guid" => row["provider_submission_id"]})
               |> json_response(200)
    end
  end

  describe "till signing" do
    setup ctx do
      ctx.owner
      |> send_json(:put, "#{ctx.admin}/fiscal/identity", %{
        "legal_name" => "Box Berlin GmbH",
        "country_code" => "DE",
        "tax_id" => "2181508150",
        "street" => "Torstraße",
        "building_number" => "1",
        "postal_code" => "10119",
        "city" => "Berlin"
      })
      |> json_response(200)

      :ok
    end

    test "connect the TSE, see signatures with what they print, retry", ctx do
      path = "#{ctx.admin}/fiscal/till-connections/tse"

      assert %{"connection" => nil} = ctx.accountant |> get_json(path) |> json_response(200)

      assert %{"errors" => %{"device" => ["not_for_country"]}} =
               ctx.owner
               |> send_json(:put, "#{ctx.admin}/fiscal/till-connections/rksv", %{
                 "environment" => "sandbox"
               })
               |> json_response(422)

      assert %{"connection" => %{"status" => "active", "provider" => "sandbox"} = connection} =
               ctx.owner
               |> send_json(:put, path, %{"environment" => "sandbox"})
               |> json_response(200)

      refute Map.has_key?(connection, "admin_pin")
      refute Map.has_key?(connection, "api_secret")

      assert ctx.desk
             |> send_json(:put, path, %{"environment" => "sandbox"})
             |> json_response(403)

      document = issue(ctx, %{kind: "receipt", idempotency_key: "sale-1", payment_method: "cash"})
      Palee.Application.Fiscal.FiscalTillSigning.transmit(ctx.context)

      assert %{"document" => %{"till_signature" => %{"status" => "signed", "print" => print}}} =
               ctx.accountant
               |> get_json("#{ctx.admin}/fiscal/documents/#{document.id}")
               |> json_response(200)

      assert Enum.any?(print, &(&1["label"] == "Signaturzähler"))

      assert %{"total" => 1, "counts" => %{"signed" => 1}, "signatures" => [row]} =
               ctx.accountant
               |> get_json("#{ctx.admin}/fiscal/till-signatures?status=signed")
               |> json_response(200)

      assert %{"signature" => %{"id" => id, "attempts_log" => [_ | _]}} =
               ctx.accountant
               |> get_json("#{ctx.admin}/fiscal/till-signatures/#{row["id"]}")
               |> json_response(200)

      retry = "#{ctx.admin}/fiscal/till-signatures/#{id}/retry"

      assert %{"code" => "not_retryable"} =
               ctx.owner |> send_json(:post, retry, %{}) |> json_response(409)

      assert ctx.desk |> send_json(:post, retry, %{}) |> json_response(403)
      assert ctx.coach |> get_json("#{ctx.admin}/fiscal/till-signatures") |> json_response(403)

      # A null receipt is Austrian only.
      assert %{"code" => "till_not_connected"} =
               ctx.owner
               |> send_json(:post, "#{ctx.admin}/fiscal/till-signatures/null-receipts", %{})
               |> json_response(409)
    end
  end
end
