defmodule PaleeWeb.ReceivePaymentControllerTest do
  @moduledoc "ADR-222: staff record money received and get the document the billing setup calls for."
  use PaleeWeb.ConnCase, async: false

  alias Palee.{Finance, Organizations}

  import Palee.TestFixtures

  setup do
    admin = admin_fixture(%{nickname: "desk_admin"})
    member = user_fixture(%{role: :member, nickname: "desk_member"})
    {organization, context} = tenant_fixture(admin, "Desk Tenant")
    add_tenant_member(organization, member, :member)

    {:ok, package} =
      Finance.create_package(context, %{
        name: "Desk monthly",
        family: "unlimited",
        billing_period: "monthly",
        base_price_cents: 6_000
      })

    {:ok, membership} =
      Finance.upsert_membership(context, member.id, %{
        user_type_snapshot: "member",
        status: "active",
        signup_source: "admin_created"
      })

    {:ok, subscription} = Finance.assign_package(context, membership.id, package.id, %{})

    %{
      admin: admin,
      member: member,
      organization: organization,
      context: context,
      membership: membership,
      subscription: subscription
    }
  end

  defp receive(conn, %{admin: admin, organization: organization, member: member}, body) do
    conn
    |> put_bearer_token(admin)
    |> post(
      "/api/org/#{organization.slug}/admin/finance/members/#{member.id}/payments/receive",
      body
    )
  end

  defp document_mode(context, mode) do
    {:ok, _settings} = Finance.update_finance_settings(context, %{document_mode: mode})
  end

  test "an invoice-mode box issues a paid invoice for a package paid by card",
       %{conn: conn} = ctx do
    document_mode(ctx.context, "invoice")

    received =
      conn
      |> receive(ctx, %{
        amount_cents: 6_000,
        payment_method: "card_manual",
        membership_package_subscription_id: ctx.subscription.id,
        idempotency_key: Ecto.UUID.generate()
      })
      |> json_response(201)
      |> Map.fetch!("received")

    assert received["document_type"] == "invoice"
    assert received["replayed"] == false
    assert received["invoice"]["status"] == "paid"
    assert received["invoice"]["balance_due_cents"] == 0
    assert received["invoice"]["membership_package_subscription_id"] == ctx.subscription.id
    assert received["payment"]["payment_method"] == "card_manual"
    assert received["payment"]["finance_invoice_id"] == received["invoice"]["id"]
    assert received["package_name"] == "Desk monthly"
    assert received["reference"] == received["invoice"]["invoice_number"]
  end

  test "a receipt-mode box issues a paid receipt for a described charge", %{conn: conn} = ctx do
    document_mode(ctx.context, "receipt")

    received =
      conn
      |> receive(ctx, %{
        amount_cents: 1_500,
        payment_method: "cash",
        description: "Protein bar and water",
        charge_category: "product",
        idempotency_key: Ecto.UUID.generate()
      })
      |> json_response(201)
      |> Map.fetch!("received")

    assert received["document_type"] == "receipt"
    assert received["description"] == "Protein bar and water"
    assert received["invoice"]["status"] == "paid"
    assert received["payment"]["payment_method"] == "cash"
  end

  test "paying an open invoice settles it, partly or in full", %{conn: conn} = ctx do
    {:ok, invoice} =
      Finance.create_invoice(ctx.context, ctx.membership.id, %{
        membership_package_subscription_id: ctx.subscription.id,
        amount_cents: 6_000
      })

    {:ok, _issued} = Finance.issue_invoice(ctx.context, invoice.id, %{})

    partly =
      conn
      |> receive(ctx, %{
        amount_cents: 2_000,
        payment_method: "bank_transfer",
        finance_invoice_id: invoice.id,
        idempotency_key: Ecto.UUID.generate()
      })
      |> json_response(201)
      |> Map.fetch!("received")

    assert partly["invoice"]["id"] == invoice.id
    assert partly["invoice"]["status"] == "partially_paid"
    assert partly["invoice"]["balance_due_cents"] == 4_000
    assert partly["payment"]["payment_method"] == "bank_transfer"

    assert build_conn()
           |> receive(ctx, %{
             amount_cents: 5_000,
             payment_method: "cash",
             finance_invoice_id: invoice.id,
             idempotency_key: Ecto.UUID.generate()
           })
           |> json_response(409)
           |> Map.fetch!("code") == "payment_exceeds_invoice_balance"

    rest =
      build_conn()
      |> receive(ctx, %{
        amount_cents: 4_000,
        payment_method: "cash",
        finance_invoice_id: invoice.id,
        idempotency_key: Ecto.UUID.generate()
      })
      |> json_response(201)
      |> Map.fetch!("received")

    assert rest["invoice"]["status"] == "paid"

    assert build_conn()
           |> receive(ctx, %{
             amount_cents: 1,
             payment_method: "cash",
             finance_invoice_id: invoice.id,
             idempotency_key: Ecto.UUID.generate()
           })
           |> json_response(409)
           |> Map.fetch!("code") == "invoice_already_paid"
  end

  test "a retried request records the money once and answers the same", %{conn: conn} = ctx do
    body = %{
      amount_cents: 6_000,
      payment_method: "cash",
      membership_package_subscription_id: ctx.subscription.id,
      idempotency_key: Ecto.UUID.generate()
    }

    first = conn |> receive(ctx, body) |> json_response(201) |> Map.fetch!("received")
    again = build_conn() |> receive(ctx, body) |> json_response(200) |> Map.fetch!("received")

    assert again["replayed"] == true
    assert again["payment"]["id"] == first["payment"]["id"]
    assert again["invoice"]["id"] == first["invoice"]["id"]

    profile = Finance.get_member_profile(ctx.context, ctx.member.id)
    assert length(profile.payments) == 1
  end

  test "refuses a payment without a purpose, method or key", %{conn: conn} = ctx do
    assert conn
           |> receive(ctx, %{
             amount_cents: 1_000,
             payment_method: "cash",
             idempotency_key: Ecto.UUID.generate()
           })
           |> json_response(422)
           |> Map.fetch!("code") == "payment_purpose_required"

    assert build_conn()
           |> receive(ctx, %{amount_cents: 1_000, payment_method: "crypto", idempotency_key: "k"})
           |> json_response(422)

    assert build_conn()
           |> receive(ctx, %{amount_cents: 1_000, payment_method: "cash"})
           |> json_response(422)
  end

  test "front desk (take_payments, not manage_billing) may record it", %{conn: conn} = ctx do
    desk = user_fixture(%{role: :member, nickname: "front_desk"})
    add_tenant_member(ctx.organization, desk, :front_desk)

    conn
    |> put_bearer_token(desk)
    |> post(
      "/api/org/#{ctx.organization.slug}/admin/finance/members/#{ctx.member.id}/payments/receive",
      %{
        amount_cents: 6_000,
        payment_method: "cash",
        membership_package_subscription_id: ctx.subscription.id,
        idempotency_key: Ecto.UUID.generate()
      }
    )
    |> json_response(201)
  end

  defp tenant_fixture(user, name) do
    {:ok, organization} =
      Organizations.create_organization(%{name: "#{name} #{System.unique_integer([:positive])}"})

    add_tenant_member(organization, user, :owner)
    {:ok, context} = Organizations.resolve_tenant_context(user, organization.slug)
    {organization, context}
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
