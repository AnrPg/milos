defmodule PaleeWeb.AdminFiscalTaxControllerTest do
  @moduledoc """
  ADR-244/245 over HTTP: tax categories, US sales tax rates, document PDF
  and HTML, accounting export formats, settings and downloads. Reads need
  `view_finance_reports`, writes `manage_billing`.
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
    {_coach_user, coach} = staff.(:coach)

    {:ok, context} =
      Organizations.resolve_tenant_context(owner_user, Organizations.legacy_organization_slug())

    %{
      context: context,
      owner_user: owner_user,
      owner: owner,
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

  @identity %{
    "legal_name" => "CrossFit Αθήνα ΙΚΕ",
    "country_code" => "GR",
    "tax_id" => "090000045",
    "tax_office" => "Α' Αθηνών",
    "street" => "Ερμού",
    "postal_code" => "10563",
    "city" => "Αθήνα"
  }

  test "coaches cannot read or change taxes and exports", ctx do
    assert ctx.coach |> get_json("#{ctx.admin}/fiscal/tax-categories") |> json_response(403)
    assert ctx.coach |> get_json("#{ctx.admin}/fiscal/exports/formats") |> json_response(403)

    assert ctx.coach
           |> send_json(:put, "#{ctx.admin}/fiscal/exports/settings/datev", %{"options" => %{}})
           |> json_response(403)
  end

  test "tax categories follow the business's country; sales tax is US only", ctx do
    assert %{"country" => nil, "default" => "standard"} =
             ctx.owner |> get_json("#{ctx.admin}/fiscal/tax-categories") |> json_response(200)

    ctx.owner |> send_json(:put, "#{ctx.admin}/fiscal/identity", @identity) |> json_response(200)

    assert %{"country" => "GR", "categories" => categories, "max_exemption_reason" => 300} =
             ctx.owner |> get_json("#{ctx.admin}/fiscal/tax-categories") |> json_response(200)

    assert "reduced" in categories
    refute "sales_tax" in categories

    assert %{"applies" => false, "rates" => [], "states" => states} =
             ctx.owner |> get_json("#{ctx.admin}/fiscal/sales-tax-rates") |> json_response(200)

    assert "NY" in states

    assert %{"code" => "sales_tax_not_applicable"} =
             ctx.owner
             |> send_json(:put, "#{ctx.admin}/fiscal/sales-tax-rates", %{
               "rates" => [%{"state" => "NY", "rate_bp" => 400}]
             })
             |> json_response(409)
  end

  describe "with a document" do
    setup ctx do
      ctx.owner |> send_json(:put, "#{ctx.admin}/fiscal/identity", @identity) |> json_response(200)
      now = DateTime.utc_now()
      today = Organizations.local_date(ctx.context, now)

      {:ok, document, :issued} =
        Fiscal.issue(
          ctx.context,
          %{
            kind: "receipt",
            issue_date: today,
            idempotency_key: "tax-sale-1",
            payment_method: "cash",
            lines: [%{description: "Μηνιαία συνδρομή", quantity: 1, unit_price_cents: 6000}]
          },
          ctx.owner_user.id,
          now
        )

      %{document: document, today: Date.to_iso8601(today)}
    end

    test "downloads the document as PDF and HTML", ctx do
      path = "#{ctx.admin}/fiscal/documents/#{ctx.document.id}"

      conn = ctx.owner |> get_json("#{path}/pdf")
      assert conn.status == 200
      assert get_resp_header(conn, "content-type") |> hd() =~ "application/pdf"
      assert get_resp_header(conn, "content-disposition") |> hd() =~ "R-000001.pdf"
      assert "%PDF-" <> _rest = conn.resp_body

      conn = ctx.owner |> get_json("#{path}/html?language=en")
      assert conn.status == 200
      assert conn.resp_body =~ "Tax ID (AFM)"
      assert conn.resp_body =~ "090000045"

      assert ctx.owner |> get_json("#{path}/pdf?language=pt") |> json_response(422)

      assert ctx.owner
             |> get_json("#{ctx.admin}/fiscal/documents/#{Ecto.UUID.generate()}/pdf")
             |> json_response(404)
    end

    test "lists formats, saves settings and downloads exports", ctx do
      assert %{"formats" => formats, "settings" => settings} =
               ctx.owner |> get_json("#{ctx.admin}/fiscal/exports/formats") |> json_response(200)

      assert Enum.map(formats, & &1["id"]) == ~w(datev xero quickbooks sage bexio csv json)
      assert Enum.all?(settings, &(&1["saved"] == false))

      settings_path = "#{ctx.admin}/fiscal/exports/settings"

      assert %{"code" => "validation_failed", "errors" => %{"options.chart" => ["invalid"]}} =
               ctx.owner
               |> send_json(:put, "#{settings_path}/datev", %{"options" => %{"chart" => "SKR99"}})
               |> json_response(422)

      assert ctx.owner
             |> send_json(:put, "#{settings_path}/nope", %{"options" => %{}})
             |> json_response(404)

      export = "#{ctx.admin}/fiscal/exports"
      range = "from=#{ctx.today}&to=#{ctx.today}"

      assert %{"errors" => %{"options.consultant_number" => ["required"]}} =
               ctx.owner |> get_json("#{export}/datev?#{range}") |> json_response(422)

      assert %{"setting" => %{"format" => "datev", "saved" => true, "options" => options}} =
               ctx.owner
               |> send_json(:put, "#{settings_path}/datev", %{
                 "options" => %{"consultant_number" => 29_098, "client_number" => 55_003}
               })
               |> json_response(200)

      assert options["chart"] == "SKR03"

      conn = ctx.owner |> get_json("#{export}/datev?#{range}")
      assert conn.status == 200
      assert get_resp_header(conn, "content-type") |> hd() =~ "windows-1252"
      assert get_resp_header(conn, "x-palee-export-documents") == ["1"]
      assert get_resp_header(conn, "content-disposition") |> hd() =~ "EXTF_Buchungsstapel_"
      assert ~s("EXTF";700;21;"Buchungsstapel") <> _rest = conn.resp_body
      assert conn.resp_body =~ ~s(60,00;"S";"EUR";;;;1000;8400)

      conn = ctx.owner |> get_json("#{export}/json?#{range}")
      assert %{"documents" => [%{"number" => "R-000001"}]} = Jason.decode!(conn.resp_body)

      assert ctx.owner |> get_json("#{export}/nope?#{range}") |> json_response(404)

      assert %{"code" => "invalid_date_range"} =
               ctx.owner
               |> get_json("#{export}/csv?from=2027-02-02&to=2027-02-01")
               |> json_response(422)
    end
  end
end
