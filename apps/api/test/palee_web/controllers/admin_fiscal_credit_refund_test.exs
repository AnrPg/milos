defmodule PaleeWeb.AdminFiscalCreditRefundTest do
  @moduledoc """
  ADR-265 end to end with the sandbox payment provider: a receipt paid
  online offers «refund to the card»; the credit note issued with it is the
  one the refund issues (ADR-262), with the chosen reason, and a repeated
  click makes no second refund and no second note.
  """
  use PaleeWeb.ConnCase, async: false

  alias Palee.{Finance, Fiscal, Organizations}

  import Palee.TestFixtures

  @identity %{
    "legal_name" => "CrossFit Κυψέλη ΙΚΕ",
    "country_code" => "GR",
    "tax_id" => "090000045",
    "tax_office" => "Ζ' Αθηνών",
    "street" => "Φωκίωνος Νέγρη",
    "postal_code" => "11361",
    "city" => "Αθήνα"
  }

  setup %{conn: conn} do
    admin = admin_fixture(%{nickname: "cr_admin"})
    member = user_fixture(%{role: :member, nickname: "cr_member"})

    {:ok, organization} =
      Organizations.create_organization(%{
        name: "Credit Refund #{System.unique_integer([:positive])}"
      })

    add_tenant_member(organization, admin, :owner)
    add_tenant_member(organization, member, :member)
    {:ok, context} = Organizations.resolve_tenant_context(admin, organization.slug)

    {:ok, membership} =
      Finance.upsert_membership(context, member.id, %{
        user_type_snapshot: "member",
        status: "active",
        signup_source: "admin_created"
      })

    {:ok, invoice} =
      Finance.create_invoice(context, membership.id, %{
        amount_cents: 6_000,
        description: "Μηνιαία συνδρομή",
        due_date: Date.add(Date.utc_today(), -1)
      })

    {:ok, invoice} = Finance.issue_invoice(context, invoice.id, %{})

    ctx = %{
      admin: admin,
      member: member,
      organization: organization,
      context: context,
      invoice: invoice
    }

    conn
    |> as(admin)
    |> put(admin_path(ctx, "/fiscal/identity"), @identity)
    |> json_response(200)

    conn
    |> as(admin)
    |> put(admin_path(ctx, "/payments/account"), %{provider: "sandbox", environment: "test"})
    |> json_response(200)

    ctx
  end

  defp admin_path(ctx, path), do: "/api/org/#{ctx.organization.slug}/admin#{path}"
  defp me_path(ctx, path), do: "/api/org/#{ctx.organization.slug}/me#{path}"
  defp as(conn, user), do: put_bearer_token(conn, user)

  defp pay_online(conn, ctx) do
    payment =
      conn
      |> as(ctx.member)
      |> post(me_path(ctx, "/invoices/#{ctx.invoice.id}/pay"), %{
        idempotency_key: "credit-refund-pay-1"
      })
      |> json_response(200)
      |> Map.fetch!("payment")

    ref = URI.decode_query(URI.parse(payment["redirect_url"]).query)["sandbox_checkout"]

    conn
    |> as(ctx.member)
    |> post(me_path(ctx, "/payments/sandbox/complete"), %{provider_ref: ref, outcome: "succeeded"})
    |> json_response(200)
    |> Map.fetch!("payment")
  end

  test "a receipt paid online is credited and refunded in one action", %{conn: conn} = ctx do
    paid = pay_online(conn, ctx)
    assert paid["fulfilment_status"] == "done"

    receipt = Fiscal.document_by_key(ctx.context, "finance-payment:" <> paid["finance_payment_id"])
    assert receipt.gross_cents == 6_000
    path = admin_path(ctx, "/fiscal/documents/#{receipt.id}")

    detail = conn |> as(ctx.admin) |> get(path) |> json_response(200) |> Map.fetch!("document")

    assert %{"card_last4" => "4242", "refundable_cents" => 6_000, "provider" => "sandbox"} =
             detail["refund_option"]

    body = %{idempotency_key: "panel-key-0001", reason: "billing_error", refund: true}

    first =
      conn
      |> as(ctx.admin)
      |> post("#{path}/credit-notes", body)
      |> json_response(201)

    assert %{"status" => "succeeded", "amount_cents" => 6_000} = first["refund"]

    assert %{"kind" => "credit_note", "credit_reason" => "billing_error", "gross_cents" => 6_000} =
             first["document"]

    # The refund issued the note: exactly one, and a repeat changes nothing.
    again =
      conn
      |> as(ctx.admin)
      |> post("#{path}/credit-notes", body)
      |> json_response(200)

    assert again["document"]["id"] == first["document"]["id"]
    assert again["refund"]["id"] == first["refund"]["id"]
    assert [%{id: note_id}] = Fiscal.credit_notes(ctx.context, receipt.id)
    assert note_id == first["document"]["id"]

    detail = conn |> as(ctx.admin) |> get(path) |> json_response(200) |> Map.fetch!("document")
    assert detail["refund_option"] == nil
  end

  test "a document not paid online cannot be refunded from the panel", %{conn: conn} = ctx do
    now = DateTime.utc_now()

    {:ok, cash, :issued} =
      Fiscal.issue(
        ctx.context,
        %{
          kind: "receipt",
          issue_date: Organizations.local_date(ctx.context, now),
          idempotency_key: "cash-sale-1",
          payment_method: "cash",
          lines: [%{description: "Drop-in", quantity: 1, unit_price_cents: 1_500}]
        },
        ctx.admin.id,
        now
      )

    path = admin_path(ctx, "/fiscal/documents/#{cash.id}")
    assert conn |> as(ctx.admin) |> get(path) |> json_response(200)
    |> get_in(["document", "refund_option"]) == nil

    assert %{"code" => "refund_not_available"} =
             conn
             |> as(ctx.admin)
             |> post("#{path}/credit-notes", %{
               idempotency_key: "panel-key-0002",
               reason: "other",
               refund: true
             })
             |> json_response(409)

    assert Fiscal.credit_notes(ctx.context, cash.id) == []
  end

  defp add_tenant_member(organization, user, role) do
    {:ok, membership} =
      Organizations.add_membership(%{
        organization_id: organization.id,
        user_id: user.id,
        role: role,
        status: :active,
        joined_at: DateTime.utc_now()
      })

    membership
  end
end
