defmodule MilosTrainingWeb.FinanceAccountingControllerTest do
  @moduledoc "ADR-116 HTTP contract, run as the RLS-enforcing runtime role (ConnCase default)."

  use MilosTrainingWeb.ConnCase, async: false

  import MilosTraining.TestFixtures

  alias MilosTraining.{Finance, Organizations}

  defp tenant(name) do
    bypass_rls(fn ->
      admin = admin_fixture()
      member = user_fixture(%{role: :member})

      {:ok, organization} =
        Organizations.create_organization(%{
          name: "#{name} #{System.unique_integer([:positive])}"
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

      {:ok, membership} =
        Finance.upsert_membership(context, member.id, %{
          user_type_snapshot: "member",
          status: "active",
          signup_source: "admin_created"
        })

      {:ok, payment} =
        Finance.record_payment(context, membership.id, %{
          amount_cents: 6_000,
          payment_method: "cash",
          payment_status: "paid",
          paid_on: Date.utc_today()
        })

      %{organization: organization, admin: admin, member: member, payment: payment}
    end)
  end

  defp admin_path(tenant, path), do: "/api/org/#{tenant.organization.slug}/admin#{path}"
  defp me_path(tenant, path), do: "/api/org/#{tenant.organization.slug}/me#{path}"

  defp refund!(conn, tenant, amount_cents) do
    conn
    |> put_bearer_token(tenant.admin)
    |> post(
      admin_path(
        tenant,
        "/finance/members/#{tenant.member.id}/payments/#{tenant.payment.id}/reversals"
      ),
      %{amount_cents: amount_cents, reason: "Injury", request_id: Ecto.UUID.generate()}
    )
    |> json_response(201)
  end

  test "a refund returns its receipt; staff and the member can read and print it", %{conn: conn} do
    tenant = tenant("Receipt API Gym")
    other = tenant("Receipt API Other")

    response = refund!(conn, tenant, 2_500)
    receipt = response["refund_receipt"]
    assert response["payment_reversal"]["amount_cents"] == 2_500
    refute Map.has_key?(response["payment_reversal"], "refund_receipt")
    assert receipt["receipt_number"] == "RFD-000001"
    assert receipt["integrity_verified"] == true

    assert %{"refund_receipts" => [%{"id" => id}]} =
             build_conn()
             |> put_bearer_token(tenant.admin)
             |> get(admin_path(tenant, "/finance/refund-receipts?q=RFD"))
             |> json_response(200)

    assert id == receipt["id"]

    assert %{"refund_receipt" => %{"snapshot" => %{"receipt_number" => "RFD-000001"}}} =
             build_conn()
             |> put_bearer_token(tenant.admin)
             |> get(admin_path(tenant, "/finance/refund-receipts/#{id}"))
             |> json_response(200)

    document =
      build_conn()
      |> put_bearer_token(tenant.admin)
      |> get(admin_path(tenant, "/finance/refund-receipts/#{id}/document?locale=de"))

    assert document.status == 200
    assert [content_type] = get_resp_header(document, "content-type")
    assert content_type =~ "text/html"
    assert [csp] = get_resp_header(document, "content-security-policy")
    assert csp =~ "default-src 'none'"
    assert document.resp_body =~ "Erstattungsbeleg"
    assert document.resp_body =~ "25.00 EUR"

    assert %{"refund_receipts" => [%{"id" => ^id}]} =
             build_conn()
             |> put_bearer_token(tenant.member)
             |> get(me_path(tenant, "/refund-receipts"))
             |> json_response(200)

    assert build_conn()
           |> put_bearer_token(tenant.member)
           |> get(me_path(tenant, "/refund-receipts/#{id}/document"))
           |> response(200) =~ "RFD-000001"

    # Another tenant's staff cannot read it through their own organization.
    assert build_conn()
           |> put_bearer_token(other.admin)
           |> get(admin_path(other, "/finance/refund-receipts/#{id}"))
           |> json_response(404)

    # A member cannot use the staff endpoints.
    assert build_conn()
           |> put_bearer_token(tenant.member)
           |> get(admin_path(tenant, "/finance/refund-receipts"))
           |> response(403)
  end

  test "another member of the same tenant cannot read someone else's receipt", %{conn: conn} do
    tenant = tenant("Receipt Privacy Gym")
    %{"refund_receipt" => %{"id" => id}} = refund!(conn, tenant, 1_000)

    stranger =
      bypass_rls(fn ->
        stranger = user_fixture(%{role: :member})

        {:ok, _} =
          Organizations.add_membership(%{
            organization_id: tenant.organization.id,
            user_id: stranger.id,
            role: :member,
            status: :active,
            joined_at: DateTime.utc_now()
          })

        stranger
      end)

    assert build_conn()
           |> put_bearer_token(stranger)
           |> get(me_path(tenant, "/refund-receipts/#{id}"))
           |> json_response(404)

    assert %{"refund_receipts" => []} =
             build_conn()
             |> put_bearer_token(stranger)
             |> get(me_path(tenant, "/refund-receipts"))
             |> json_response(200)
  end

  test "reconciliation lines are idempotent and match internal payments", %{conn: conn} do
    tenant = tenant("Recon API Gym")

    body = %{
      provider: "viva_wallet",
      external_reference: "txn-001",
      external_type: "payment",
      statement_amount_cents: 6_000,
      statement_currency: "EUR",
      statement_occurred_on: Date.to_iso8601(Date.utc_today())
    }

    created =
      conn
      |> put_bearer_token(tenant.admin)
      |> post(admin_path(tenant, "/finance/reconciliation-records"), body)
      |> json_response(201)

    record_id = created["reconciliation_record"]["id"]
    assert created["idempotent_replay"] == false

    assert %{"idempotent_replay" => true, "reconciliation_record" => %{"id" => ^record_id}} =
             build_conn()
             |> put_bearer_token(tenant.admin)
             |> post(admin_path(tenant, "/finance/reconciliation-records"), body)
             |> json_response(200)

    assert %{"code" => "reconciliation_reference_conflict"} =
             build_conn()
             |> put_bearer_token(tenant.admin)
             |> post(
               admin_path(tenant, "/finance/reconciliation-records"),
               %{body | statement_amount_cents: 5_999}
             )
             |> json_response(409)

    assert build_conn()
           |> put_bearer_token(tenant.admin)
           |> post(admin_path(tenant, "/finance/reconciliation-records"), %{provider: "x"})
           |> json_response(422)

    assert %{"candidates" => [%{"target_id" => target_id, "target_type" => "payment"}]} =
             build_conn()
             |> put_bearer_token(tenant.admin)
             |> get(admin_path(tenant, "/finance/reconciliation-records/#{record_id}/candidates"))
             |> json_response(200)

    assert target_id == tenant.payment.id

    assert %{"reconciliation_record" => %{"status" => "matched"}} =
             build_conn()
             |> put_bearer_token(tenant.admin)
             |> post(
               admin_path(tenant, "/finance/reconciliation-records/#{record_id}/match"),
               %{target_type: "payment", target_id: target_id}
             )
             |> json_response(200)

    assert %{"reconciliation_records" => [%{"status" => "matched"}]} =
             build_conn()
             |> put_bearer_token(tenant.admin)
             |> get(admin_path(tenant, "/finance/reconciliation-records?status=matched"))
             |> json_response(200)

    assert %{"reconciliation_record" => %{"status" => "unmatched"}} =
             build_conn()
             |> put_bearer_token(tenant.admin)
             |> post(
               admin_path(tenant, "/finance/reconciliation-records/#{record_id}/unmatch"),
               %{}
             )
             |> json_response(200)
  end

  test "an accounting export completes inline and is downloadable", %{conn: conn} do
    tenant = tenant("Export API Gym")
    other = tenant("Export API Other")
    refund!(conn, tenant, 1_000)
    today = Date.to_iso8601(Date.utc_today())

    export =
      build_conn()
      |> put_bearer_token(tenant.admin)
      |> post(admin_path(tenant, "/finance/accounting-exports"), %{
        range_start: today,
        range_end: today
      })
      |> json_response(201)
      |> Map.fetch!("accounting_export")

    assert export["status"] == "completed"
    assert export["row_counts"]["refund_receipts"] == 1
    assert length(export["files"]) == 10

    assert %{"download_url" => url, "expires_in_seconds" => 900} =
             build_conn()
             |> put_bearer_token(tenant.admin)
             |> get(admin_path(tenant, "/finance/accounting-exports/#{export["id"]}/download"))
             |> json_response(200)

    assert url =~ "organizations/#{tenant.organization.id}/finance/accounting-exports/"

    assert %{"accounting_exports" => [%{"id" => id}]} =
             build_conn()
             |> put_bearer_token(tenant.admin)
             |> get(admin_path(tenant, "/finance/accounting-exports"))
             |> json_response(200)

    assert id == export["id"]

    assert build_conn()
           |> put_bearer_token(other.admin)
           |> get(admin_path(other, "/finance/accounting-exports/#{export["id"]}/download"))
           |> json_response(404)

    assert %{"code" => "invalid_export_range"} =
             build_conn()
             |> put_bearer_token(tenant.admin)
             |> post(admin_path(tenant, "/finance/accounting-exports"), %{
               range_start: today,
               range_end: Date.to_iso8601(Date.add(Date.utc_today(), -1))
             })
             |> json_response(422)
  end
end
