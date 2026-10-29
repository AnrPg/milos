defmodule PaleeWeb.AdminFiscalControllerTest do
  @moduledoc """
  ADR-240–242 over HTTP: owners and accountants manage the legal identity,
  read documents, issue credit notes, verify the journal and download the
  archive; front desk (by default) and coaches cannot.
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

  @identity %{
    "legal_name" => "CrossFit Αθήνα ΙΚΕ",
    "country_code" => "GR",
    "tax_id" => "090000045",
    "tax_office" => "Α' Αθηνών",
    "street" => "Ερμού",
    "postal_code" => "10563",
    "city" => "Αθήνα"
  }

  test "countries list the MVP markets with their rules", ctx do
    body = ctx.owner |> get_json("#{ctx.admin}/fiscal/countries") |> json_response(200)
    countries = Map.new(body["countries"], &{&1["country"], &1})

    assert Map.keys(countries) |> Enum.sort() ==
             ~w(AT BE CH CY DE FR GB GR LI LU MC US)

    assert countries["GR"]["authority"] == "mydata"
    assert countries["FR"]["register"] == "nf525"
    assert countries["DE"]["till_device"] == "tse"
    assert countries["CH"]["currency"] == "CHF"
  end

  test "the identity is saved field by field with errors per field", ctx do
    assert %{"identity" => nil, "complete" => false} =
             ctx.owner |> get_json("#{ctx.admin}/fiscal/identity") |> json_response(200)

    assert %{"code" => "validation_failed", "errors" => %{"tax_id" => ["check_digit"]}} =
             ctx.owner
             |> send_json(:put, "#{ctx.admin}/fiscal/identity", %{
               @identity
               | "tax_id" => "090000046"
             })
             |> json_response(422)

    assert %{
             "complete" => true,
             "identity" => %{"currency" => "EUR"},
             "profile" => %{"country" => "GR"}
           } =
             ctx.owner
             |> send_json(:put, "#{ctx.admin}/fiscal/identity", @identity)
             |> json_response(200)

    assert %{"complete" => true} =
             ctx.accountant |> get_json("#{ctx.admin}/fiscal/identity") |> json_response(200)
  end

  test "coaches and front desk (by default) have no access", ctx do
    assert ctx.coach |> get_json("#{ctx.admin}/fiscal/identity") |> json_response(403)

    assert ctx.desk
           |> send_json(:put, "#{ctx.admin}/fiscal/identity", @identity)
           |> json_response(403)
  end

  describe "with documents" do
    setup ctx do
      ctx.owner
      |> send_json(:put, "#{ctx.admin}/fiscal/identity", @identity)
      |> json_response(200)

      now = DateTime.utc_now()

      {:ok, document, :issued} =
        Fiscal.issue(
          ctx.context,
          %{
            kind: "receipt",
            issue_date: Organizations.local_date(ctx.context, now),
            idempotency_key: "sale-1",
            lines: [%{description: "Μηνιαία συνδρομή", quantity: 2, unit_price_cents: 6000}]
          },
          ctx.owner_user.id,
          now
        )

      %{document: document}
    end

    test "lists, shows and credits a document idempotently", ctx do
      assert %{"total" => 1, "documents" => [%{"number" => "R-000001"}]} =
               ctx.accountant
               |> get_json("#{ctx.admin}/fiscal/documents?kind=receipt")
               |> json_response(200)

      path = "#{ctx.admin}/fiscal/documents/#{ctx.document.id}"

      assert %{
               "document" => %{
                 "lines" => [%{"quantity" => 2}],
                 "credit_notes" => [],
                 "credit_reason" => nil,
                 "refund_option" => nil
               }
             } = ctx.owner |> get_json(path) |> json_response(200)

      body = %{
        "idempotency_key" => "credit-0001",
        "reason" => "product_return",
        "lines" => [%{"position" => 1, "quantity" => 1}]
      }

      # ADR-265: staff always give the reason.
      assert ctx.owner
             |> send_json(:post, "#{path}/credit-notes", Map.delete(body, "reason"))
             |> json_response(422)

      assert ctx.owner
             |> send_json(:post, "#{path}/credit-notes", %{body | "reason" => "whim"})
             |> json_response(422)

      assert %{
               "document" => %{
                 "number" => "C-000001",
                 "gross_cents" => 6000,
                 "credit_reason" => "product_return"
               },
               "refund" => nil
             } =
               ctx.owner |> send_json(:post, "#{path}/credit-notes", body) |> json_response(201)

      assert %{"document" => %{"number" => "C-000001"}} =
               ctx.owner |> send_json(:post, "#{path}/credit-notes", body) |> json_response(200)

      # The same key with another reason is another request.
      assert %{"code" => "idempotency_key_reused"} =
               ctx.owner
               |> send_json(:post, "#{path}/credit-notes", %{body | "reason" => "other"})
               |> json_response(409)

      assert %{"document" => %{"credit_notes" => [%{"credit_reason" => "product_return"}]}} =
               ctx.owner |> get_json(path) |> json_response(200)

      assert %{"code" => "credit_exceeds_document"} =
               ctx.owner
               |> send_json(:post, "#{path}/credit-notes", %{
                 "idempotency_key" => "credit-0002",
                 "reason" => "billing_error",
                 "lines" => [%{"position" => 1, "quantity" => 2}]
               })
               |> json_response(422)

      # The reason is part of the journal and the journal still verifies.
      assert %{"verification" => %{"valid" => true}} =
               ctx.owner
               |> get_json("#{ctx.admin}/fiscal/journal/verification")
               |> json_response(200)
    end

    test "verifies the journal and downloads the archive", ctx do
      assert %{"verification" => %{"valid" => true, "entries" => 2}} =
               ctx.owner
               |> get_json("#{ctx.admin}/fiscal/journal/verification")
               |> json_response(200)

      today = Organizations.local_date(ctx.context, DateTime.utc_now()) |> Date.to_iso8601()
      conn = ctx.owner |> get_json("#{ctx.admin}/fiscal/archive?from=#{today}&to=#{today}")
      assert conn.status == 200
      assert get_resp_header(conn, "content-type") |> hd() =~ "application/zip"
      assert {:ok, _files} = :zip.unzip(conn.resp_body, [:memory])

      assert %{"code" => "invalid_date_range"} =
               ctx.owner
               |> get_json("#{ctx.admin}/fiscal/archive?from=2027-02-02&to=2027-02-01")
               |> json_response(422)
    end

    test "closings are listed", ctx do
      assert %{"closings" => []} =
               ctx.owner |> get_json("#{ctx.admin}/fiscal/closings") |> json_response(200)
    end
  end
end
