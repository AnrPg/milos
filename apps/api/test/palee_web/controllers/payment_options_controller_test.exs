defmodule PaleeWeb.PaymentOptionsControllerTest do
  @moduledoc """
  ADR-260 end to end with the sandbox provider: what members pay online,
  and a declined saved card: the member hears about it each time, it waits
  in the Ουρές queue, staff send the card link again, charge once more or
  close it, and staff hear when no retry is left.
  """
  use PaleeWeb.ConnCase, async: false

  alias Palee.{Finance, Notifications, Organizations, Payments}
  alias Palee.Application.Payments.OnlinePayments

  import Palee.TestFixtures

  setup do
    admin = admin_fixture(%{nickname: "opt_admin"})
    member = user_fixture(%{role: :member, nickname: "opt_member"})

    {:ok, organization} =
      Organizations.create_organization(%{
        name: "Options Tenant #{System.unique_integer([:positive])}"
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

  # A saved card that the sandbox always declines later.
  defp declining_card(conn, ctx) do
    invoice = open_invoice(ctx.context, ctx.membership, 6_500)

    payment =
      conn
      |> as(ctx.member)
      |> post(me_path(ctx, "/invoices/#{invoice.id}/pay"), %{
        idempotency_key: "opt-pay-#{System.unique_integer([:positive])}",
        save_card: true,
        consent_accepted: true
      })
      |> json_response(200)
      |> Map.fetch!("payment")

    ref = URI.decode_query(URI.parse(payment["redirect_url"]).query)["sandbox_checkout"]

    conn
    |> as(ctx.member)
    |> post(me_path(ctx, "/payments/sandbox/complete"), %{
      provider_ref: ref,
      outcome: "succeeded",
      decline_card: true
    })
    |> json_response(200)

    [method] = Payments.methods(ctx.context, ctx.member.id)
    method
  end

  defp types(user_id) do
    user_id |> Notifications.list_for_user() |> Enum.map(&to_string(&1.type))
  end

  test "every purpose is online by default; staff switch one off", %{conn: conn} = ctx do
    status = connect_sandbox(conn, ctx)

    assert status["account"]["options"] == %{
             "purposes" => %{
               "packages" => true,
               "autopay" => true,
               "drop_in" => true,
               "shop" => true,
               "personal_training" => true
             },
             "notify_member" => true,
             "notify_staff" => true
           }

    changed =
      conn
      |> as(ctx.admin)
      |> put(admin_path(ctx, "/payments/account/options"), %{
        purposes: %{autopay: false},
        notify_staff: false
      })
      |> json_response(200)

    assert changed["account"]["options"]["purposes"]["autopay"] == false
    assert changed["account"]["options"]["purposes"]["packages"] == true
    assert changed["account"]["options"]["notify_staff"] == false
    refute Payments.available?(ctx.context, "autopay")
    assert Payments.available?(ctx.context, "packages")

    # Switching providers keeps the options.
    connect_sandbox(conn, ctx)
    refute Payments.available?(ctx.context, "autopay")

    # Autopay is off: a member's chosen card is not charged.
    method = declining_card(conn, ctx)
    {:ok, _} = Payments.set_autopay(ctx.context, ctx.member.id, method.id, true)
    open_invoice(ctx.context, ctx.membership, 6_000)
    assert OnlinePayments.autopay(%{organization_id: ctx.organization.id}) == 0
  end

  test "options are validated field by field", %{conn: conn} = ctx do
    conn
    |> as(ctx.admin)
    |> put(admin_path(ctx, "/payments/account/options"), %{notify_member: false})
    |> json_response(409)
    |> then(&assert(&1["code"] == "online_payments_unavailable"))

    connect_sandbox(conn, ctx)

    assert {:error, {:invalid_fields, errors}} =
             Payments.save_options(
               ctx.context,
               %{"purposes" => %{"bingo" => true}},
               nil,
               DateTime.utc_now()
             )

    assert errors == %{"purposes.bingo" => "unknown"}
  end

  test "a declined card is told to the member, queued, and handled by staff",
       %{conn: conn} = ctx do
    connect_sandbox(conn, ctx)
    method = declining_card(conn, ctx)
    invoice = open_invoice(ctx.context, ctx.membership, 6_000)
    member_context = Map.put(ctx.context, :user_id, ctx.member.id)

    {:ok, charge} =
      Payments.charge_saved(
        member_context,
        %{
          payment_method_id: method.id,
          purpose_type: "finance_invoice",
          purpose_id: invoice.id,
          amount_cents: 6_000,
          currency: "EUR",
          description: "Μηνιαία συνδρομή",
          idempotency_key: "opt-charge-1"
        },
        DateTime.utc_now()
      )

    assert charge.status == "scheduled"
    assert charge.declines == 1
    assert "payment_failed" in types(ctx.member.id)
    refute "payment_needs_attention" in types(ctx.admin.id)

    [queued] =
      conn
      |> as(ctx.admin)
      |> get(admin_path(ctx, "/payments/attention"))
      |> json_response(200)
      |> Map.fetch!("payments")

    assert queued["id"] == charge.id
    assert queued["retries"] == 3
    assert queued["member_name"] == ctx.member.nickname

    # The card link goes out again.
    conn
    |> as(ctx.admin)
    |> post(admin_path(ctx, "/payments/#{charge.id}/card-link"))
    |> json_response(200)

    assert Enum.count(types(ctx.member.id), &(&1 == "payment_failed")) == 2

    # One more charge now: declined again, no retry left, staff hear about it.
    failed =
      conn
      |> as(ctx.admin)
      |> post(admin_path(ctx, "/payments/#{charge.id}/retry-charge"))
      |> json_response(200)
      |> Map.fetch!("payment")

    assert failed["status"] == "failed"
    assert "payment_needs_attention" in types(ctx.admin.id)

    # The notice opens the failed charges in Οικονομικά › Ουρές.
    staff_notice =
      ctx.admin.id
      |> Notifications.list_for_user()
      |> Enum.find(&(to_string(&1.type) == "payment_needs_attention"))

    assert (staff_notice.payload["url"] || staff_notice.payload[:url]) ==
             "/admin/finance?tab=queues&queue=failed_charges"

    # Closed by staff (paid at the desk): leaves the queue, no more retries.
    conn
    |> as(ctx.admin)
    |> post(admin_path(ctx, "/payments/#{charge.id}/dismiss"))
    |> json_response(200)
    |> then(&assert(&1["payment"]["attention_resolution"] == "dismissed"))

    assert conn
           |> as(ctx.admin)
           |> get(admin_path(ctx, "/payments/attention"))
           |> json_response(200)
           |> Map.fetch!("payments") == []

    conn
    |> as(ctx.admin)
    |> post(admin_path(ctx, "/payments/#{charge.id}/retry-charge"))
    |> json_response(409)
    |> then(&assert(&1["code"] == "payment_not_retryable"))

    # A member cannot use the staff queue.
    conn
    |> as(ctx.member)
    |> get(admin_path(ctx, "/payments/attention"))
    |> json_response(403)
  end

  test "a member switched off for failure notices hears nothing", %{conn: conn} = ctx do
    connect_sandbox(conn, ctx)

    {:ok, _} =
      Payments.save_options(ctx.context, %{notify_member: false}, nil, DateTime.utc_now())

    method = declining_card(conn, ctx)
    invoice = open_invoice(ctx.context, ctx.membership, 6_000)

    {:ok, _charge} =
      Payments.charge_saved(
        Map.put(ctx.context, :user_id, ctx.member.id),
        %{
          payment_method_id: method.id,
          purpose_type: "finance_invoice",
          purpose_id: invoice.id,
          amount_cents: 6_000,
          currency: "EUR",
          description: "Μηνιαία συνδρομή",
          idempotency_key: "opt-charge-2"
        },
        DateTime.utc_now()
      )

    refute "payment_failed" in types(ctx.member.id)
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
