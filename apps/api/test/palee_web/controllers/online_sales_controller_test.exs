defmodule PaleeWeb.OnlineSalesControllerTest do
  @moduledoc """
  ADR-248 end to end with the sandbox provider: a box sells a package
  online (public page), a member buys it and books the class they wanted
  once paid, and withdraws within 14 days for the unused part.
  """
  use PaleeWeb.ConnCase, async: false

  alias Palee.{Finance, Organizations, Payments}
  alias Palee.Application.{PublishBoxPublicProfile, UpdateBoxPublicProfile}

  import Palee.TestFixtures

  setup do
    owner = admin_fixture(%{nickname: "sale_owner"})
    member = user_fixture(%{role: :member, nickname: "sale_member"})

    {:ok, organization} =
      Organizations.create_organization(%{
        name: "Sale Tenant #{System.unique_integer([:positive])}"
      })

    add_tenant_member(organization, owner, :owner)
    add_tenant_member(organization, member, :member)
    {:ok, context} = Organizations.resolve_tenant_context(owner, organization.slug)

    {:ok, package} =
      Finance.create_package(context, %{
        name: "Μηνιαίο απεριόριστο",
        family: "unlimited",
        billing_period: "monthly",
        base_price_cents: 6_000
      })

    {:ok, hidden} =
      Finance.create_package(context, %{
        name: "Εταιρικό",
        family: "unlimited",
        billing_period: "monthly",
        base_price_cents: 4_000
      })

    %{
      owner: owner,
      member: member,
      organization: organization,
      context: context,
      package: package,
      hidden: hidden
    }
  end

  defp admin_path(ctx, path), do: "/api/org/#{ctx.organization.slug}/admin#{path}"
  defp me_path(ctx, path), do: "/api/org/#{ctx.organization.slug}/me#{path}"

  defp sell_online(conn, ctx, package) do
    conn
    |> put_bearer_token(ctx.owner)
    |> patch(admin_path(ctx, "/finance/packages/#{package.id}"), %{sold_online: true})
    |> json_response(200)
  end

  defp keep_at_desk(conn, ctx, package) do
    conn
    |> put_bearer_token(ctx.owner)
    |> patch(admin_path(ctx, "/finance/packages/#{package.id}"), %{sold_online: false})
    |> json_response(200)
  end

  defp connect_sandbox(conn, ctx) do
    conn
    |> put_bearer_token(ctx.owner)
    |> put(admin_path(ctx, "/payments/account"), %{provider: "sandbox", environment: "test"})
    |> json_response(200)
  end

  defp complete(conn, ctx, payment) do
    ref = URI.decode_query(URI.parse(payment["redirect_url"]).query)["sandbox_checkout"]

    conn
    |> put_bearer_token(ctx.member)
    |> post(me_path(ctx, "/payments/sandbox/complete"), %{provider_ref: ref, outcome: "succeeded"})
    |> json_response(200)
    |> Map.fetch!("payment")
  end

  test "the public page lists only packages sold online", %{conn: conn} = ctx do
    sell_online(conn, ctx, ctx.package)
    # ADR-291: a package never chosen is listed for the desk; the owner's «off» is not.
    keep_at_desk(conn, ctx, ctx.hidden)

    {:ok, profile} =
      UpdateBoxPublicProfile.call(ctx.context, %{"about" => "Box", "disciplines" => ["crossfit"]})

    {:ok, _profile} =
      PublishBoxPublicProfile.publish(ctx.context, %{"lock_version" => profile.lock_version})

    page =
      build_conn()
      |> get("/api/public/boxes/#{ctx.organization.slug}/packages")
      |> json_response(200)

    assert [%{"name" => "Μηνιαίο απεριόριστο", "base_price_cents" => 6_000}] = page["packages"]
    assert page["withdrawal_days"] == 14
    refute page["online_payments"]
  end

  test "a package not sold online cannot be bought", %{conn: conn} = ctx do
    # ADR-271: the owner's «off» survives the automatic opening on connect.
    keep_at_desk(conn, ctx, ctx.hidden)

    connect_sandbox(conn, ctx)

    conn
    |> put_bearer_token(ctx.member)
    |> post(me_path(ctx, "/packages/#{ctx.hidden.id}/buy"), %{
      idempotency_key: "buy-hidden-1",
      start_now: true
    })
    |> json_response(409)
    |> then(&assert(&1["code"] == "package_not_for_sale"))
  end

  test "buying a package, then withdrawing within 14 days", %{conn: conn} = ctx do
    sell_online(conn, ctx, ctx.package)
    connect_sandbox(conn, ctx)

    terms =
      conn
      |> put_bearer_token(ctx.member)
      |> get(me_path(ctx, "/packages/#{ctx.package.id}/purchase-terms?language=el"))
      |> json_response(200)

    assert terms["available"]
    assert terms["withdrawal_days"] == 14
    assert terms["start_now_text"] =~ "14 ημέρες"

    # The express request to start now is required where withdrawal applies.
    conn
    |> put_bearer_token(ctx.member)
    |> post(me_path(ctx, "/packages/#{ctx.package.id}/buy"), %{idempotency_key: "buy-pkg-0"})
    |> json_response(422)
    |> then(&assert(&1["code"] == "start_now_consent_required"))

    payment =
      conn
      |> put_bearer_token(ctx.member)
      |> post(me_path(ctx, "/packages/#{ctx.package.id}/buy"), %{
        idempotency_key: "buy-pkg-1",
        start_now: true,
        language: "el"
      })
      |> json_response(200)
      |> Map.fetch!("payment")

    assert payment["amount_cents"] == 6_000
    assert payment["purpose_type"] == "membership_package"

    paid = complete(conn, ctx, payment)
    assert paid["status"] == "succeeded"
    assert paid["fulfilment_status"] == "done"

    %{membership: membership, package_subscriptions: subscriptions} =
      Finance.get_member_profile(ctx.context, ctx.member.id)

    assert membership

    assert Enum.any?(
             subscriptions,
             &(&1.membership_package_id == ctx.package.id and &1.status == "active")
           )

    # A retried fulfilment never assigns the package twice.
    Payments.process(ctx.context, :due, DateTime.utc_now())

    assert ctx.context
           |> Finance.get_member_profile(ctx.member.id)
           |> Map.fetch!(:package_subscriptions)
           |> Enum.count(&(&1.membership_package_id == ctx.package.id)) == 1

    withdrawal =
      conn
      |> put_bearer_token(ctx.member)
      |> post(me_path(ctx, "/payments/#{payment["id"]}/withdraw"))
      |> json_response(200)

    # Same day, nothing used: everything back.
    assert withdrawal["refunded_cents"] == 6_000

    assert ctx.context
           |> Finance.get_member_profile(ctx.member.id)
           |> Map.fetch!(:package_subscriptions)
           |> Enum.all?(&(&1.status == "cancelled"))

    conn
    |> put_bearer_token(ctx.member)
    |> post(me_path(ctx, "/payments/#{payment["id"]}/withdraw"))
    |> json_response(409)
  end

  test "buying a package books the class the member wanted once it is paid",
       %{conn: conn} = ctx do
    sell_online(conn, ctx, ctx.package)
    keep_at_desk(conn, ctx, ctx.hidden)
    connect_sandbox(conn, ctx)

    workout = workout_fixture(ctx.owner, %{tenant_context: ctx.context})

    slot =
      slot_fixture(workout, %{
        tenant_context: ctx.context,
        auto_approve: true,
        scheduled_at:
          DateTime.add(DateTime.truncate(DateTime.utc_now(), :second), 86_400, :second)
      })

    payment =
      conn
      |> put_bearer_token(ctx.member)
      |> post(me_path(ctx, "/packages/#{ctx.package.id}/buy"), %{
        idempotency_key: "buy-book-1",
        start_now: true,
        book_slot_id: slot.id
      })
      |> json_response(200)
      |> Map.fetch!("payment")

    assert payment["metadata"]["book_slot_id"] == slot.id
    paid = complete(conn, ctx, payment)
    assert paid["fulfilment_status"] == "done"

    assert Palee.Repo.get_by(Palee.Scheduling.Booking,
             scheduled_class_id: slot.id,
             user_id: ctx.member.id
           )
  end

  test "the public page and the terms name the provider and the package's in-person services",
       %{conn: conn} = ctx do
    sell_online(conn, ctx, ctx.package)
    keep_at_desk(conn, ctx, ctx.hidden)
    connect_sandbox(conn, ctx)

    {:ok, profile} =
      UpdateBoxPublicProfile.call(ctx.context, %{"about" => "Box", "disciplines" => ["crossfit"]})

    {:ok, _profile} =
      PublishBoxPublicProfile.publish(ctx.context, %{"lock_version" => profile.lock_version})

    page =
      build_conn()
      |> get("/api/public/boxes/#{ctx.organization.slug}/packages")
      |> json_response(200)

    assert page["online_payments"]
    assert page["provider"] == "sandbox"
    assert [%{"services" => services}] = page["packages"]
    assert services["group_classes.included"] == true

    terms =
      conn
      |> put_bearer_token(ctx.member)
      |> get(me_path(ctx, "/packages/#{ctx.package.id}/purchase-terms?language=en"))
      |> json_response(200)

    assert terms["provider"] == "sandbox"
  end

  test "choosing autopay keeps the saved card for what falls due", %{conn: conn} = ctx do
    sell_online(conn, ctx, ctx.package)
    connect_sandbox(conn, ctx)

    payment =
      conn
      |> put_bearer_token(ctx.member)
      |> post(me_path(ctx, "/packages/#{ctx.package.id}/buy"), %{
        idempotency_key: "buy-auto-1",
        start_now: true,
        save_card: true,
        consent_accepted: true,
        autopay: true,
        language: "el"
      })
      |> json_response(200)
      |> Map.fetch!("payment")

    assert payment["metadata"]["autopay"] == true
    assert complete(conn, ctx, payment)["status"] == "succeeded"

    assert [%{"autopay" => true, "status" => "active"}] =
             conn
             |> put_bearer_token(ctx.member)
             |> get(me_path(ctx, "/payment-methods"))
             |> json_response(200)
             |> Map.fetch!("payment_methods")
  end

  test "autopay without saving the card is ignored", %{conn: conn} = ctx do
    sell_online(conn, ctx, ctx.package)
    connect_sandbox(conn, ctx)

    payment =
      conn
      |> put_bearer_token(ctx.member)
      |> post(me_path(ctx, "/packages/#{ctx.package.id}/buy"), %{
        idempotency_key: "buy-auto-2",
        start_now: true,
        autopay: true
      })
      |> json_response(200)
      |> Map.fetch!("payment")

    refute Map.has_key?(payment["metadata"], "autopay")
  end

  test "a drop-in bought for one class has no withdrawal and needs no start-now request",
       %{conn: conn} = ctx do
    connect_sandbox(conn, ctx)

    {:ok, drop_in} =
      Finance.create_package(ctx.context, %{
        name: "Μία επίσκεψη",
        package_type: "drop_in",
        base_price_cents: 1_500
      })

    sell_online(conn, ctx, drop_in)

    workout = workout_fixture(ctx.owner, %{tenant_context: ctx.context})

    slot =
      slot_fixture(workout, %{
        tenant_context: ctx.context,
        auto_approve: true,
        scheduled_at:
          DateTime.add(DateTime.truncate(DateTime.utc_now(), :second), 86_400, :second)
      })

    terms =
      conn
      |> put_bearer_token(ctx.member)
      |> get(me_path(ctx, "/packages/#{drop_in.id}/purchase-terms?book_slot_id=#{slot.id}"))
      |> json_response(200)

    assert terms["withdrawal_days"] == nil
    assert terms["start_now_text"] == nil

    # Without the class it is an ordinary purchase with the 14 days.
    assert conn
           |> put_bearer_token(ctx.member)
           |> get(me_path(ctx, "/packages/#{drop_in.id}/purchase-terms"))
           |> json_response(200)
           |> Map.fetch!("withdrawal_days") == 14

    payment =
      conn
      |> put_bearer_token(ctx.member)
      |> post(me_path(ctx, "/packages/#{drop_in.id}/buy"), %{
        idempotency_key: "buy-drop-1",
        book_slot_id: slot.id
      })
      |> json_response(200)
      |> Map.fetch!("payment")

    assert payment["metadata"]["withdrawal"] == %{"applies" => false}
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
