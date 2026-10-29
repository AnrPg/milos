defmodule PaleeWeb.PaymentsControllerTest do
  @moduledoc """
  ADR-246/247 end to end with the sandbox provider: staff connect the
  account, a member pays an open invoice on the provider's page and saves
  the card, Finance records an "online" payment, staff refund it, a later
  invoice is paid automatically with the saved card (and dunned when the
  card declines), and webhooks only make Palee ask again.
  """
  use PaleeWeb.ConnCase, async: false

  alias Palee.{Finance, Organizations, Payments}
  alias Palee.Infrastructure.Payments.SandboxGateway
  alias Palee.Application.Payments.OnlinePayments

  import Palee.TestFixtures

  setup do
    admin = admin_fixture(%{nickname: "pay_admin"})
    member = user_fixture(%{role: :member, nickname: "pay_member"})
    other = user_fixture(%{role: :member, nickname: "pay_other"})

    {:ok, organization} =
      Organizations.create_organization(%{
        name: "Pay Tenant #{System.unique_integer([:positive])}"
      })

    add_tenant_member(organization, admin, :owner)
    add_tenant_member(organization, member, :member)
    add_tenant_member(organization, other, :member)
    {:ok, context} = Organizations.resolve_tenant_context(admin, organization.slug)

    {:ok, membership} =
      Finance.upsert_membership(context, member.id, %{
        user_type_snapshot: "member",
        status: "active",
        signup_source: "admin_created"
      })

    %{
      admin: admin,
      member: member,
      other: other,
      organization: organization,
      context: context,
      membership: membership,
      invoice: open_invoice(context, membership, 6_500)
    }
  end

  defp open_invoice(context, membership, cents) do
    {:ok, invoice} =
      Finance.create_invoice(context, membership.id, %{
        amount_cents: cents,
        description: "Μηνιαία συνδρομή",
        due_date: Date.add(Date.utc_today(), -1)
      })

    {:ok, invoice} = Finance.issue_invoice(context, invoice.id, %{})
    invoice
  end

  defp admin_path(ctx, path), do: "/api/org/#{ctx.organization.slug}/admin#{path}"
  defp me_path(ctx, path), do: "/api/org/#{ctx.organization.slug}/me#{path}"

  defp as(conn, user), do: put_bearer_token(conn, user)

  defp connect_sandbox(conn, ctx) do
    conn
    |> as(ctx.admin)
    |> put(admin_path(ctx, "/payments/account"), %{provider: "sandbox", environment: "test"})
    |> json_response(200)
  end

  defp pay(conn, ctx, user, invoice, body) do
    conn
    |> as(user)
    |> post(me_path(ctx, "/invoices/#{invoice.id}/pay"), body)
  end

  defp complete(conn, ctx, user, payment, outcome, decline_card \\ false) do
    ref = URI.decode_query(URI.parse(payment["redirect_url"]).query)["sandbox_checkout"]

    conn
    |> as(user)
    |> post(me_path(ctx, "/payments/sandbox/complete"), %{
      provider_ref: ref,
      outcome: outcome,
      decline_card: decline_card
    })
    |> json_response(200)
    |> Map.fetch!("payment")
  end

  test "staff connect the sandbox; credentials are never returned", %{conn: conn} = ctx do
    status = connect_sandbox(conn, ctx)
    assert status["account"]["provider"] == "sandbox"
    assert status["account"]["status"] == "active"
    assert status["account"]["webhook_url"] =~ "/api/webhooks/payments/#{ctx.organization.id}/"
    refute Map.has_key?(status["account"], "credentials")

    # Viva needs its credentials.
    conn
    |> as(ctx.admin)
    |> put(admin_path(ctx, "/payments/account"), %{provider: "viva", environment: "test"})
    |> json_response(422)
    |> then(&assert(&1["errors"]["client_id"] == ["required"]))
  end

  test "a member cannot pay before the business connects a provider", %{conn: conn} = ctx do
    conn
    |> pay(ctx, ctx.member, ctx.invoice, %{idempotency_key: Ecto.UUID.generate()})
    |> json_response(409)
    |> then(&assert(&1["code"] == "online_payments_unavailable"))
  end

  test "paying, saving the card, refunding, then paying the next invoice automatically",
       %{conn: conn} = ctx do
    connect_sandbox(conn, ctx)

    terms =
      conn
      |> as(ctx.member)
      |> get(me_path(ctx, "/invoices/#{ctx.invoice.id}/payment-terms?language=el"))
      |> json_response(200)

    assert terms["available"]
    assert terms["amount_cents"] == 6_500
    assert terms["consent_text"] =~ "Επιτρέπω"

    # Saving the card needs consent.
    conn
    |> pay(ctx, ctx.member, ctx.invoice, %{idempotency_key: "first-pay-1", save_card: true})
    |> json_response(422)
    |> then(&assert(&1["code"] == "consent_required"))

    payment =
      conn
      |> pay(ctx, ctx.member, ctx.invoice, %{
        idempotency_key: "first-pay-2",
        save_card: true,
        consent_accepted: true,
        language: "el"
      })
      |> json_response(200)
      |> Map.fetch!("payment")

    assert payment["status"] == "awaiting_payer"
    assert payment["redirect_url"] =~ "sandbox_checkout="

    # Another member cannot see it.
    conn
    |> as(ctx.other)
    |> get(me_path(ctx, "/payments/#{payment["id"]}"))
    |> json_response(404)

    paid = complete(conn, ctx, ctx.member, payment, "succeeded")
    assert paid["status"] == "succeeded"
    assert paid["card_last4"] == "4242"
    assert paid["fulfilment_status"] == "done"
    assert paid["finance_payment_id"]

    {:ok, invoice} = Finance.get_invoice(ctx.context, ctx.invoice.id)
    assert invoice.status == "paid"

    [method] =
      conn
      |> as(ctx.member)
      |> get(me_path(ctx, "/payment-methods"))
      |> json_response(200)
      |> Map.fetch!("payment_methods")

    assert method["max_amount_cents"] == 6_500
    assert method["consent_version"]

    # Staff refund part of it; Finance records the reversal.
    refund =
      conn
      |> as(ctx.admin)
      |> post(admin_path(ctx, "/payments/#{payment["id"]}/refunds"), %{
        amount_cents: 1_500,
        reason: "Λάθος χρέωση",
        idempotency_key: "refund-key-1"
      })
      |> json_response(200)
      |> Map.fetch!("refund")

    assert refund["status"] == "succeeded"

    detail =
      conn
      |> as(ctx.admin)
      |> get(admin_path(ctx, "/payments/#{payment["id"]}"))
      |> json_response(200)
      |> Map.fetch!("payment")

    assert detail["refunded_cents"] == 1_500
    assert [%{"amount_cents" => 1_500}] = detail["refunds"]

    conn
    |> as(ctx.admin)
    |> post(admin_path(ctx, "/payments/#{payment["id"]}/refunds"), %{
      amount_cents: 5_001,
      idempotency_key: "refund-key-2"
    })
    |> json_response(422)

    # Automatic payment of the next due invoice with the saved card.
    conn
    |> as(ctx.member)
    |> put(me_path(ctx, "/payment-methods/#{method["id"]}/autopay"), %{autopay: true})
    |> json_response(200)

    next = open_invoice(ctx.context, ctx.membership, 6_000)
    assert OnlinePayments.autopay(%{organization_id: ctx.organization.id}) == 1

    {:ok, next} = Finance.get_invoice(ctx.context, next.id)
    assert next.status == "paid"

    # A price above the consent needs a new checkout.
    above = open_invoice(ctx.context, ctx.membership, 7_000)
    assert OnlinePayments.autopay(%{organization_id: ctx.organization.id}) == 0
    {:ok, above} = Finance.get_invoice(ctx.context, above.id)
    assert above.status != "paid"

    # Withdrawn consent: never charged again.
    conn
    |> as(ctx.member)
    |> delete(me_path(ctx, "/payment-methods/#{method["id"]}"))
    |> json_response(200)
    |> then(&assert(&1["payment_method"]["status"] == "revoked"))
  end

  test "a declined saved card is retried on the dunning schedule", %{conn: conn} = ctx do
    connect_sandbox(conn, ctx)

    payment =
      conn
      |> pay(ctx, ctx.member, ctx.invoice, %{
        idempotency_key: "decline-pay-1",
        save_card: true,
        consent_accepted: true
      })
      |> json_response(200)
      |> Map.fetch!("payment")

    complete(conn, ctx, ctx.member, payment, "succeeded", true)
    [method] = Payments.methods(ctx.context, ctx.member.id)
    next = open_invoice(ctx.context, ctx.membership, 6_000)
    member_context = Map.put(ctx.context, :user_id, ctx.member.id)

    {:ok, charge} =
      Payments.charge_saved(
        member_context,
        %{
          payment_method_id: method.id,
          purpose_type: "finance_invoice",
          purpose_id: next.id,
          amount_cents: 6_000,
          currency: "EUR",
          description: "Next",
          idempotency_key: "charge-key-1"
        },
        DateTime.utc_now()
      )

    assert charge.status == "scheduled"
    assert charge.failure_code == "card_declined"
    assert DateTime.diff(charge.next_attempt_at, DateTime.utc_now(), :hour) in 23..24
  end

  test "webhooks are deduplicated and only make Palee ask the provider", %{conn: conn} = ctx do
    status = connect_sandbox(conn, ctx)
    account_id = status["account"]["id"]

    payment =
      conn
      |> pay(ctx, ctx.member, ctx.invoice, %{idempotency_key: "hook-pay-1"})
      |> json_response(200)
      |> Map.fetch!("payment")

    ref = URI.decode_query(URI.parse(payment["redirect_url"]).query)["sandbox_checkout"]
    {:ok, transaction} = Payments.sandbox_transaction(ref, "succeeded", false)

    body =
      Jason.encode!(%{event_id: "evt-1", provider_ref: ref, transaction_id: transaction})

    post_hook = fn body, signature ->
      build_conn()
      |> put_req_header("content-type", "application/json")
      |> put_req_header("x-sandbox-signature", signature)
      |> post("/api/webhooks/payments/#{ctx.organization.id}/#{account_id}", body)
    end

    assert post_hook.(body, "forged") |> json_response(400)
    assert post_hook.(body, SandboxGateway.sign(body)) |> json_response(200)
    assert post_hook.(body, SandboxGateway.sign(body)) |> json_response(200)

    {:ok, paid} = Payments.get(ctx.context, payment["id"])
    assert paid.status == "succeeded"
    assert paid.fulfilment_status == "done"
  end

  test "staff never record an online payment at the desk", %{conn: conn} = ctx do
    conn
    |> as(ctx.admin)
    |> post(admin_path(ctx, "/finance/members/#{ctx.member.id}/payments/receive"), %{
      amount_cents: 6_500,
      payment_method: "online",
      finance_invoice_id: ctx.invoice.id,
      idempotency_key: Ecto.UUID.generate()
    })
    |> json_response(422)
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
