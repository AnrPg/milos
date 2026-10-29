defmodule PaleeWeb.TerminalPaymentsControllerTest do
  @moduledoc """
  ADR-249 end to end: staff open a Tap to Pay payment at the desk, the
  phone posts what the Viva.com Terminal app returned, and Palee records
  `card_terminal` money with the ADR-222 document only after Viva (stubbed
  with Req.Test) confirms the transaction. Cancel, decline, duplicates, an
  unconfirmed result and a lost one are covered, with the sandbox app too.
  """
  use PaleeWeb.ConnCase, async: false

  alias Palee.{Finance, Organizations, Payments}
  alias Palee.Payments.PaymentStore

  import Palee.TestFixtures

  setup do
    admin = admin_fixture(%{nickname: "tap_admin"})
    member = user_fixture(%{role: :member, nickname: "tap_member"})

    {:ok, organization} =
      Organizations.create_organization(%{
        name: "Tap Tenant #{System.unique_integer([:positive])}"
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

    %{
      admin: admin,
      member: member,
      organization: organization,
      context: context,
      membership: membership
    }
  end

  defp open_invoice(context, membership, cents) do
    {:ok, invoice} =
      Finance.create_invoice(context, membership.id, %{
        amount_cents: cents,
        description: "Μηνιαία συνδρομή",
        due_date: Date.utc_today()
      })

    {:ok, invoice} = Finance.issue_invoice(context, invoice.id, %{})
    invoice
  end

  defp tpath(ctx, rest), do: "/api/org/#{ctx.organization.slug}/admin/payments/terminal#{rest}"
  defp as(conn, user), do: put_bearer_token(conn, user)

  defp connect_viva(ctx) do
    {:ok, _account} =
      PaymentStore.save_account(ctx.context, %{
        provider: "viva",
        environment: "test",
        status: "active",
        credentials: %{
          "client_id" => "cid",
          "client_secret" => "csecret",
          "merchant_id" => "mid",
          "api_key" => "akey"
        },
        settings: %{"source_code" => "1234"}
      })
  end

  defp connect_sandbox(conn, ctx) do
    conn
    |> as(ctx.admin)
    |> put("/api/org/#{ctx.organization.slug}/admin/payments/account", %{
      provider: "sandbox",
      environment: "test"
    })
    |> json_response(200)
  end

  defp start(conn, ctx, body) do
    conn
    |> as(ctx.admin)
    |> post(tpath(ctx, ""), Map.put_new(body, :idempotency_key, "tap-" <> Ecto.UUID.generate()))
  end

  defp result(conn, ctx, body) do
    conn
    |> as(ctx.admin)
    |> post(tpath(ctx, "/result"), body)
  end

  # Viva answers: a token, and the transaction `id` as `transaction` says.
  defp stub_viva(transactions) do
    Req.Test.stub(Palee.PaymentsHttp, fn
      %{host: "demo-accounts.vivapayments.com"} = conn ->
        Req.Test.json(conn, %{"access_token" => "tok", "expires_in" => 3600})

      %{host: "demo-api.vivapayments.com", request_path: "/checkout/v2/transactions/" <> id} =
          conn ->
        case Map.get(transactions, id) do
          nil -> Plug.Conn.send_resp(conn, 404, "")
          :down -> Plug.Conn.send_resp(conn, 503, "")
          body -> Req.Test.json(conn, body)
        end

      %{host: "demo.vivapayments.com", request_path: "/api/transactions"} = conn ->
        listed =
          transactions
          |> Enum.filter(fn {_id, body} -> is_map(body) end)
          |> Enum.map(fn {id, body} ->
            %{"TransactionId" => id, "MerchantTrns" => body["merchantTrns"], "StatusId" => "F"}
          end)

        Req.Test.json(conn, %{"Transactions" => listed, "ErrorCode" => 0})
    end)
  end

  defp viva_paid(payment, cents \\ nil) do
    %{
      "statusId" => "F",
      "amount" => (cents || payment["amount_cents"]) / 100,
      "currencyCode" => "978",
      "merchantTrns" => payment["reference"],
      "insDate" => DateTime.to_iso8601(DateTime.utc_now()),
      "cardNumber" => "479275XXXXXX9999",
      "cardType" => "VISA"
    }
  end

  defp payments_of(ctx) do
    %{payments: payments} = Finance.get_member_profile(ctx.context, ctx.member.id)
    payments
  end

  test "an invoice paid by a card tapped at the desk, confirmed with Viva", %{conn: conn} = ctx do
    connect_viva(ctx)
    invoice = open_invoice(ctx.context, ctx.membership, 4_500)

    assert %{"available" => true} =
             conn |> as(ctx.admin) |> get(tpath(ctx, "/availability")) |> json_response(200)

    %{"payment" => payment} =
      conn
      |> start(ctx, %{
        purpose: "finance_invoice",
        purpose_id: invoice.id,
        user_id: ctx.member.id,
        amount_cents: 4_500,
        idempotency_key: "tap-invoice-1"
      })
      |> json_response(201)

    assert payment["initiation"] == "terminal"
    assert payment["status"] == "awaiting_payer"
    assert payment["currency"] == "EUR"
    request = payment["app_request"]
    assert request["scheme"] == "vivapayclient://pay/v1"
    assert request["params"]["clientTransactionId"] == payment["reference"]
    assert request["params"]["amount"] == "4500"
    assert request["params"]["callback"] == "palee-terminal://result"
    assert request["url"] =~ "vivapayclient://pay/v1?"

    # A retry answers the same payment.
    assert %{"payment" => %{"id" => same}} =
             conn
             |> start(ctx, %{
               purpose: "finance_invoice",
               purpose_id: invoice.id,
               user_id: ctx.member.id,
               amount_cents: 4_500,
               idempotency_key: "tap-invoice-1"
             })
             |> json_response(201)

    assert same == payment["id"]

    stub_viva(%{"tx-1" => viva_paid(payment)})

    paid =
      conn
      |> result(ctx, %{
        reference: payment["reference"],
        status: "success",
        transaction_id: "tx-1",
        message: "Transaction successful"
      })
      |> json_response(200)
      |> Map.fetch!("payment")

    assert paid["status"] == "succeeded"
    assert paid["provider_transaction_id"] == "tx-1"
    assert paid["card_last4"] == "9999"
    assert paid["fulfilment_status"] == "done"
    assert paid["finance_payment_id"]
    assert paid["app_request"] == nil

    {:ok, invoice} = Finance.get_invoice(ctx.context, invoice.id)
    assert invoice.status == "paid"

    assert [%{payment_method: "card_terminal"} = recorded] = payments_of(ctx)
    assert recorded.id == paid["finance_payment_id"]

    # Duplicate callbacks change nothing and record nothing again.
    for _ <- 1..2 do
      assert %{"payment" => %{"status" => "succeeded"}} =
               conn
               |> result(ctx, %{
                 reference: payment["reference"],
                 status: "success",
                 transaction_id: "tx-1"
               })
               |> json_response(200)
    end

    assert [_one] = payments_of(ctx)

    # The request was used: another transaction for it is refused.
    conn
    |> result(ctx, %{reference: payment["reference"], status: "success", transaction_id: "tx-2"})
    |> json_response(409)
    |> then(&assert(&1["code"] == "terminal_request_used"))
  end

  test "a free sale leaves the document the billing setup calls for", %{conn: conn} = ctx do
    connect_viva(ctx)
    {:ok, _settings} = Finance.update_finance_settings(ctx.context, %{document_mode: "receipt"})

    %{"payment" => payment} =
      conn
      |> start(ctx, %{
        purpose: "free_sale",
        user_id: ctx.member.id,
        amount_cents: 1_200,
        description: "Πρωτεΐνη",
        charge_category: "product"
      })
      |> json_response(201)

    assert payment["purpose_type"] == "free_sale"
    stub_viva(%{"tx-free" => viva_paid(payment)})

    assert %{"payment" => %{"status" => "succeeded", "fulfilment_status" => "done"}} =
             conn
             |> result(ctx, %{
               reference: payment["reference"],
               status: "success",
               transaction_id: "tx-free"
             })
             |> json_response(200)

    assert [%{payment_method: "card_terminal", amount_cents: 1_200} = recorded] = payments_of(ctx)
    {:ok, receipt} = Finance.get_invoice(ctx.context, recorded.finance_invoice_id)
    assert receipt.status == "paid"
    assert (receipt.params || %{})["document_kind"] == "receipt"
  end

  test "the phone's word is never enough", %{conn: conn} = ctx do
    connect_viva(ctx)

    open = fn ->
      conn
      |> start(ctx, %{
        purpose: "free_sale",
        user_id: ctx.member.id,
        amount_cents: 2_000,
        description: "Personal training"
      })
      |> json_response(201)
      |> Map.fetch!("payment")
    end

    # Viva took another amount: never paid in Palee's books.
    short = open.()
    stub_viva(%{"tx-short" => viva_paid(short, 200)})

    assert %{"payment" => %{"status" => "failed", "failure_code" => "amount_mismatch"}} =
             conn
             |> result(ctx, %{
               reference: short["reference"],
               status: "success",
               transaction_id: "tx-short"
             })
             |> json_response(200)

    # Another request's transaction.
    stolen = open.()
    stub_viva(%{"tx-stolen" => Map.put(viva_paid(stolen), "merchantTrns", short["reference"])})

    assert %{"payment" => %{"status" => "failed", "failure_code" => "reference_mismatch"}} =
             conn
             |> result(ctx, %{
               reference: stolen["reference"],
               status: "success",
               transaction_id: "tx-stolen"
             })
             |> json_response(200)

    # A forged or foreign reference names nothing.
    conn
    |> result(ctx, %{
      reference: "pt1.#{stolen["id"]}.forged",
      status: "success",
      transaction_id: "tx-x"
    })
    |> json_response(404)

    assert payments_of(ctx) == []
  end

  test "cancel and decline on the phone; a later confirmed transaction still counts",
       %{conn: conn} = ctx do
    connect_viva(ctx)

    open = fn key ->
      conn
      |> start(ctx, %{
        purpose: "free_sale",
        user_id: ctx.member.id,
        amount_cents: 1_500,
        description: "Drop-in",
        idempotency_key: key
      })
      |> json_response(201)
      |> Map.fetch!("payment")
    end

    cancelled = open.("tap-cancel-1")

    assert %{"payment" => %{"status" => "cancelled", "failure_code" => "terminal_cancelled"}} =
             conn
             |> result(ctx, %{reference: cancelled["reference"], status: "cancelled"})
             |> json_response(200)

    # The terminal app did take the card after all: Viva confirms it.
    stub_viva(%{"tx-late" => viva_paid(cancelled)})

    assert %{"payment" => %{"status" => "succeeded"}} =
             conn
             |> result(ctx, %{
               reference: cancelled["reference"],
               status: "success",
               transaction_id: "tx-late"
             })
             |> json_response(200)

    # A decline with a transaction is confirmed as declined at Viva.
    declined = open.("tap-decline-1")

    stub_viva(%{
      "tx-declined" => %{
        "statusId" => "E",
        "amount" => 15,
        "currencyCode" => "978",
        "errorText" => "Declined"
      }
    })

    assert %{"payment" => %{"status" => "failed", "failure_code" => "viva_E"}} =
             conn
             |> result(ctx, %{
               reference: declined["reference"],
               status: "fail",
               message: "(-12) TRANSACTION_DECLINED_BY_SERVER",
               transaction_id: "tx-declined"
             })
             |> json_response(200)

    # The same Viva transaction can never pay a second request.
    another = open.("tap-another-1")
    stub_viva(%{"tx-late" => viva_paid(cancelled)})

    conn
    |> result(ctx, %{reference: another["reference"], status: "success", transaction_id: "tx-late"})
    |> json_response(409)
    |> then(&assert(&1["code"] == "terminal_transaction_used"))

    # Staff give up on a request with no transaction.
    assert %{"payment" => %{"status" => "cancelled"}} =
             conn
             |> as(ctx.admin)
             |> post(tpath(ctx, "/#{another["id"]}/cancel"))
             |> json_response(200)

    assert [%{payment_method: "card_terminal", amount_cents: 1_500}] = payments_of(ctx)
  end

  test "an unconfirmed result stays pending and the worker settles it", %{conn: conn} = ctx do
    connect_viva(ctx)

    %{"payment" => payment} =
      conn
      |> start(ctx, %{
        purpose: "free_sale",
        user_id: ctx.member.id,
        amount_cents: 3_000,
        description: "Πακέτο"
      })
      |> json_response(201)

    stub_viva(%{"tx-slow" => :down})

    pending =
      conn
      |> result(ctx, %{reference: payment["reference"], status: "success", transaction_id: "tx-slow"})
      |> json_response(200)
      |> Map.fetch!("payment")

    assert pending["status"] == "awaiting_payer"
    assert pending["failure_code"] == "terminal_unconfirmed"
    assert pending["next_attempt_at"]
    assert payments_of(ctx) == []

    # Viva answers later; the payments worker asks again.
    stub_viva(%{"tx-slow" => viva_paid(payment)})
    later = DateTime.add(DateTime.utc_now(), 60, :second)
    assert %{succeeded: 1, fulfilled: 1} = Payments.process(ctx.context, :due, later)

    {:ok, settled} = Payments.get(ctx.context, payment["id"])
    assert settled.status == "succeeded"
    assert [%{payment_method: "card_terminal"}] = payments_of(ctx)
  end

  test "a result that never reached the phone is found by its reference", %{conn: conn} = ctx do
    connect_viva(ctx)

    %{"payment" => payment} =
      conn
      |> start(ctx, %{
        purpose: "free_sale",
        user_id: ctx.member.id,
        amount_cents: 900,
        description: "Water"
      })
      |> json_response(201)

    %{"payment" => lost} =
      conn
      |> start(ctx, %{
        purpose: "free_sale",
        user_id: ctx.member.id,
        amount_cents: 700,
        description: "Bar"
      })
      |> json_response(201)

    stub_viva(%{"tx-found" => viva_paid(payment)})

    # Nothing is looked for while the request may still be in use.
    assert %{succeeded: 0} = Payments.process(ctx.context, :due, DateTime.utc_now())

    after_expiry = DateTime.add(DateTime.utc_now(), 20 * 60, :second)
    assert %{succeeded: 1} = Payments.process(ctx.context, :due, after_expiry)

    {:ok, found} = Payments.get(ctx.context, payment["id"])
    assert found.status == "succeeded"
    assert found.provider_transaction_id == "tx-found"

    # The other one is never found: looked for on the schedule, then expired.
    {:ok, still} = Payments.get(ctx.context, lost["id"])
    assert still.status == "awaiting_payer"

    final =
      Enum.reduce(1..8, after_expiry, fn _step, at ->
        at = DateTime.add(at, 7 * 3_600, :second)
        Payments.process(ctx.context, :due, at)
        at
      end)

    assert final
    {:ok, expired} = Payments.get(ctx.context, lost["id"])
    assert expired.status == "expired"
    assert expired.failure_code == "terminal_no_result"
  end

  test "the sandbox terminal app, and the rules around it", %{conn: conn} = ctx do
    # Not available before an account is connected.
    conn
    |> start(ctx, %{
      purpose: "free_sale",
      user_id: ctx.member.id,
      amount_cents: 500,
      description: "Chalk"
    })
    |> json_response(409)
    |> then(&assert(&1["code"] == "terminal_payments_unavailable"))

    connect_sandbox(conn, ctx)

    # A free sale needs a member; walk-ins pay shop orders only.
    conn
    |> start(ctx, %{purpose: "free_sale", amount_cents: 500, description: "Chalk"})
    |> json_response(422)
    |> then(&assert(&1["code"] == "terminal_member_required"))

    invoice = open_invoice(ctx.context, ctx.membership, 2_000)

    # Never more than the invoice's balance.
    conn
    |> start(ctx, %{
      purpose: "finance_invoice",
      purpose_id: invoice.id,
      user_id: ctx.member.id,
      amount_cents: 2_001
    })
    |> json_response(422)
    |> then(&assert(&1["code"] == "invalid_payment_amount"))

    %{"payment" => payment} =
      conn
      |> start(ctx, %{
        purpose: "finance_invoice",
        purpose_id: invoice.id,
        user_id: ctx.member.id,
        amount_cents: 2_000
      })
      |> json_response(201)

    assert payment["app_request"]["scheme"] == "palee-sandbox-terminal://pay/v1"

    paid =
      conn
      |> as(ctx.admin)
      |> post(tpath(ctx, "/#{payment["id"]}/sandbox-complete"), %{outcome: "succeeded"})
      |> json_response(200)
      |> Map.fetch!("payment")

    assert paid["status"] == "succeeded"
    assert paid["fulfilment_status"] == "done"

    assert %{"payment" => %{"id" => id}} =
             conn |> as(ctx.admin) |> get(tpath(ctx, "/#{payment["id"]}")) |> json_response(200)

    assert id == payment["id"]

    # Listed with the other payments for staff to follow.
    assert %{"payments" => [%{"initiation" => "terminal"}]} =
             conn
             |> as(ctx.admin)
             |> get("/api/org/#{ctx.organization.slug}/admin/payments")
             |> json_response(200)

    # A paid request can no longer be cancelled.
    conn
    |> as(ctx.admin)
    |> post(tpath(ctx, "/#{payment["id"]}/cancel"))
    |> json_response(409)
    |> then(&assert(&1["code"] == "payment_not_cancellable"))
  end

  test "a package sold at the desk is assigned with its card_terminal money", %{conn: conn} = ctx do
    connect_sandbox(conn, ctx)

    {:ok, package} =
      Finance.create_package(ctx.context, %{
        name: "8 επισκέψεις",
        package_type: "class_pack",
        base_price_cents: 6_000
      })

    %{"payment" => payment} =
      conn
      |> start(ctx, %{
        purpose: "membership_package",
        purpose_id: package.id,
        user_id: ctx.member.id,
        amount_cents: 6_000
      })
      |> json_response(201)

    assert payment["description"] == "8 επισκέψεις"

    assert %{"payment" => %{"status" => "succeeded", "fulfilment_status" => "done"}} =
             conn
             |> as(ctx.admin)
             |> post(tpath(ctx, "/#{payment["id"]}/sandbox-complete"), %{outcome: "succeeded"})
             |> json_response(200)

    assert [%{payment_method: "card_terminal", membership_package_subscription_id: sub_id}] =
             payments_of(ctx)

    assert is_binary(sub_id)
  end

  test "a shop order waiting for payment is settled at the terminal", %{conn: conn} = ctx do
    connect_sandbox(conn, ctx)
    shop = "/api/org/#{ctx.organization.slug}"

    %{"variants" => [variant]} =
      conn
      |> as(ctx.admin)
      |> post("#{shop}/staff/shop/products", %{
        title: "Chalk",
        category: "accessories",
        status: "published",
        variants: [%{price_cents: 500, initial_quantity: 3}]
      })
      |> json_response(201)
      |> Map.fetch!("product")

    %{"order" => order} =
      conn
      |> as(ctx.member)
      |> post("#{shop}/me/shop/orders", %{
        lines: [%{variant_id: variant["id"], quantity: 2}],
        idempotency_key: "order-" <> Ecto.UUID.generate()
      })
      |> json_response(201)

    assert order["payment_status"] == "pending_payment"

    # Only its total.
    conn
    |> start(ctx, %{purpose: "shop_order", purpose_id: order["id"], amount_cents: 999})
    |> json_response(422)
    |> then(&assert(&1["code"] == "invalid_payment_amount"))

    %{"payment" => payment} =
      conn
      |> start(ctx, %{purpose: "shop_order", purpose_id: order["id"], amount_cents: 1_000})
      |> json_response(201)

    assert payment["user_id"] == ctx.member.id

    settled =
      conn
      |> as(ctx.admin)
      |> post(tpath(ctx, "/#{payment["id"]}/sandbox-complete"), %{outcome: "succeeded"})
      |> json_response(200)
      |> Map.fetch!("payment")

    assert settled["status"] == "succeeded"
    assert settled["fulfilment_status"] == "done"

    paid = Palee.Shop.get_order(ctx.context, order["id"])
    assert paid.payment_status == :paid
    assert paid.payment_provider == "sandbox"
    assert paid.payment_reference == settled["provider_transaction_id"]

    lineage = Finance.revenue_lineage(ctx.context, Palee.Shop.order_source_type(), order["id"])
    assert [%{id: finance_payment_id} = shop_payment] = lineage.payments
    assert finance_payment_id == settled["finance_payment_id"]
    assert Map.get(shop_payment, :payment_method) in [nil, "card_manual"]
  end

  test "staff never record card_terminal by hand; members cannot take payments",
       %{conn: conn} = ctx do
    invoice = open_invoice(ctx.context, ctx.membership, 1_000)

    conn
    |> as(ctx.admin)
    |> post(
      "/api/org/#{ctx.organization.slug}/admin/finance/members/#{ctx.member.id}/payments/receive",
      %{
        amount_cents: 1_000,
        payment_method: "card_terminal",
        finance_invoice_id: invoice.id,
        idempotency_key: Ecto.UUID.generate()
      }
    )
    |> json_response(422)

    conn
    |> start(Map.put(ctx, :admin, ctx.member), %{
      purpose: "free_sale",
      user_id: ctx.member.id,
      amount_cents: 500,
      description: "Chalk"
    })
    |> json_response(403)
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
