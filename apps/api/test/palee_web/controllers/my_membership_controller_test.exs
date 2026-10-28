defmodule PaleeWeb.MyMembershipControllerTest do
  @moduledoc """
  ADR-220 over HTTP: the member decides whether their subscription renews
  and can leave the box; staff can do both for them and mark someone as
  left. Payment reminders only ever ask for what is really owed.
  """

  use PaleeWeb.ConnCase, async: false
  use Oban.Testing, repo: Palee.Repo

  import Ecto.Query
  import Palee.TestFixtures

  alias Palee.Notifications.Notification
  alias Palee.Workers.NotificationEventJob
  alias Palee.{Finance, Organizations, Repo}

  setup %{conn: conn} do
    start_supervised!(
      {Oban, Keyword.put(Application.fetch_env!(:palee, Oban), :testing, :manual)}
    )

    owner = user_fixture()
    member = user_fixture()
    {:ok, box} = Organizations.create_organization(%{name: "Box #{System.unique_integer([:positive])}"})
    add!(box, owner, [:owner, :coach])
    add!(box, member, [:member])

    {:ok, staff} = Organizations.resolve_tenant_context(owner, box.slug)

    {:ok, package} =
      Finance.create_package(staff, %{
        code: "monthly-#{System.unique_integer([:positive])}",
        name: "Unlimited monthly",
        family: "unlimited",
        billing_period: "monthly",
        base_price_cents: 6_000
      })

    {:ok, membership} =
      Finance.upsert_membership(staff, member.id, %{
        user_type_snapshot: "member",
        status: "active",
        signup_source: "direct"
      })

    {:ok, subscription} = Finance.assign_package(staff, membership.id, package.id, %{})

    %{
      conn: conn,
      owner: owner,
      member: member,
      box: box,
      staff: staff,
      membership: membership,
      subscription: subscription,
      period_end: subscription.starts_on |> Date.shift(month: 1) |> Date.add(-1)
    }
  end

  defp authed(conn, user), do: conn |> recycle() |> put_bearer_token(user)
  defp me(ctx), do: "/api/org/#{ctx.box.slug}/me/membership"
  defp admin(ctx), do: "/api/org/#{ctx.box.slug}/admin/finance/members/#{ctx.member.id}"

  defp next_period_invoice(ctx) do
    {:ok, invoice} =
      Finance.generate_renewal_invoice(ctx.staff, ctx.membership.id, %{
        "service_period_start" => Date.add(ctx.period_end, 1)
      })

    {:ok, issued} = Finance.issue_invoice(ctx.staff, invoice.id, %{})
    issued
  end

  defp invoice_status(ctx, invoice_id) do
    profile = Finance.get_member_profile(ctx.staff, ctx.member.id)
    Enum.find(profile.invoices, &(&1.id == invoice_id)).status
  end

  defp reminded?(ctx) do
    ctx.staff
    |> Finance.memberships_needing_payment_reminder(0)
    |> Enum.any?(&(&1.membership_id == ctx.membership.id))
  end

  test "turning renewal off keeps the paid period, voids the next one and blocks renewal", ctx do
    invoice = next_period_invoice(ctx)
    assert reminded?(ctx)

    body =
      ctx.conn
      |> authed(ctx.member)
      |> put("#{me(ctx)}/subscriptions/#{ctx.subscription.id}/auto-renew", %{auto_renew: false})
      |> json_response(200)

    assert %{"auto_renew" => false, "renewal_changed_by" => "member"} = body["package_subscription"]
    assert body["package_subscription"]["ends_on"] == Date.to_iso8601(ctx.period_end)

    # The unpaid invoice for after the last day is no longer owed.
    assert invoice_status(ctx, invoice.id) == "void"
    refute reminded?(ctx)

    assert {:error, :renewal_turned_off} =
             Finance.generate_renewal_invoice(ctx.staff, ctx.membership.id, %{
               "service_period_start" => Date.add(ctx.period_end, 1)
             })

    # Turned back on before the last day: open-ended again.
    body =
      ctx.conn
      |> authed(ctx.member)
      |> put("#{me(ctx)}/subscriptions/#{ctx.subscription.id}/auto-renew", %{auto_renew: true})
      |> json_response(200)

    assert %{"auto_renew" => true, "ends_on" => nil} = body["package_subscription"]
  end

  test "a paid next period is kept when renewal stops", ctx do
    invoice = next_period_invoice(ctx)

    {:ok, _payment} =
      Finance.record_payment(ctx.staff, ctx.membership.id, %{
        amount_cents: invoice.total_cents,
        currency: "EUR",
        payment_method: "cash",
        payment_status: "paid",
        finance_invoice_id: invoice.id
      })

    body =
      ctx.conn
      |> authed(ctx.member)
      |> put("#{me(ctx)}/subscriptions/#{ctx.subscription.id}/auto-renew", %{auto_renew: false})
      |> json_response(200)

    assert Date.from_iso8601!(body["package_subscription"]["ends_on"]) ==
             invoice.service_period_end
  end

  test "the member leaves: staff hear it, future invoices go, and they can change their mind",
       ctx do
    invoice = next_period_invoice(ctx)

    body =
      ctx.conn
      |> authed(ctx.member)
      |> post("#{me(ctx)}/leave", %{reason: "Moving to Thessaloniki"})
      |> json_response(200)

    assert body["leaving_on"] == Date.to_iso8601(ctx.period_end)
    assert body["voided_invoice_count"] == 1
    assert body["outstanding_cents"] == 0
    assert body["membership"]["left_by"] == "member"
    assert body["membership"]["leave_reason"] == "Moving to Thessaloniki"
    assert invoice_status(ctx, invoice.id) == "void"
    refute reminded?(ctx)

    for job <- all_enqueued(worker: NotificationEventJob),
        do: perform_job(NotificationEventJob, job.args)

    assert [%{"leaving_on" => leaving_on, "reason" => "Moving to Thessaloniki"}] =
             bypass_rls(fn ->
               Repo.all(
                 from n in Notification,
                   where: n.type == :member_leaving and n.user_id == ^ctx.owner.id,
                   select: n.payload
               )
             end)

    assert leaving_on == Date.to_iso8601(ctx.period_end)

    # Billing shows the last day and no second «leave».
    billing = ctx.conn |> authed(ctx.member) |> get("/api/me/billing") |> json_response(200)
    [section] = billing["providers"]
    assert section["membership"]["leaving_on"] == Date.to_iso8601(ctx.period_end)
    assert section["actions"]["self_service_leave"] == false

    assert %{"code" => "member_leaving"} =
             ctx.conn |> authed(ctx.member) |> post("#{me(ctx)}/leave", %{}) |> json_response(409)

    assert %{"code" => "member_leaving"} =
             ctx.conn
             |> authed(ctx.member)
             |> put("#{me(ctx)}/subscriptions/#{ctx.subscription.id}/auto-renew", %{
               auto_renew: true
             })
             |> json_response(409)

    body = ctx.conn |> authed(ctx.member) |> delete("#{me(ctx)}/leave") |> json_response(200)
    assert body["membership"]["leaving_on"] == nil

    profile = Finance.get_member_profile(ctx.staff, ctx.member.id)
    assert [%{auto_renew: true, ends_on: nil}] = profile.package_subscriptions
  end

  test "staff mark someone gone today: what they used stays owed and reminded", ctx do
    {:ok, invoice} =
      Finance.create_invoice(ctx.staff, ctx.membership.id, %{
        amount_cents: 6_000,
        description: "This month",
        due_date: ctx.subscription.starts_on
      })

    {:ok, _issued} = Finance.issue_invoice(ctx.staff, invoice.id, %{})
    future = next_period_invoice(ctx)

    assert %{"code" => "invalid_leaving_on"} =
             ctx.conn
             |> authed(ctx.owner)
             |> post("#{admin(ctx)}/leave", %{
               leaving_on: Date.to_iso8601(Date.add(ctx.subscription.starts_on, -1))
             })
             |> json_response(422)

    body =
      ctx.conn
      |> authed(ctx.owner)
      |> post("#{admin(ctx)}/leave", %{
        leaving_on: Date.to_iso8601(ctx.subscription.starts_on),
        reason: "Stopped coming"
      })
      |> json_response(200)

    assert body["membership"]["status"] == "cancelled"
    assert body["membership"]["left_by"] == "staff"
    # The next period never began: cancelled. This month was used: still owed.
    assert body["voided_invoice_count"] == 1
    assert invoice_status(ctx, future.id) == "void"
    assert invoice_status(ctx, invoice.id) == "issued"
    assert body["outstanding_cents"] == 6_000
    assert reminded?(ctx)

    # Staff can undo it (they came back).
    body = ctx.conn |> authed(ctx.owner) |> delete("#{admin(ctx)}/leave") |> json_response(200)
    assert %{"status" => "active", "leaving_on" => nil} = body["membership"]
  end

  test "a package that has not started yet is cancelled with its invoice", ctx do
    {:ok, later} =
      Finance.assign_package(ctx.staff, ctx.membership.id, ctx.subscription.membership_package_id, %{
        starts_on: Date.add(ctx.period_end, 10)
      })

    {:ok, invoice} =
      Finance.create_invoice(ctx.staff, ctx.membership.id, %{
        amount_cents: 6_000,
        description: "Next block",
        due_date: ctx.subscription.starts_on,
        membership_package_subscription_id: later.id
      })

    {:ok, _issued} = Finance.issue_invoice(ctx.staff, invoice.id, %{})

    body = ctx.conn |> authed(ctx.member) |> post("#{me(ctx)}/leave", %{}) |> json_response(200)

    assert body["leaving_on"] == Date.to_iso8601(ctx.period_end)
    assert invoice_status(ctx, invoice.id) == "void"

    profile = Finance.get_member_profile(ctx.staff, ctx.member.id)
    assert Enum.find(profile.package_subscriptions, &(&1.id == later.id)).status == "cancelled"
  end

  test "a package that does not renew leaves the member no choice", ctx do
    {:ok, pack} =
      Finance.create_package(ctx.staff, %{name: "Ten visits", package_type: "class_pack"})

    {:ok, other} = Finance.assign_package(ctx.staff, ctx.membership.id, pack.id, %{})
    assert other.auto_renew == nil

    assert %{"code" => "renewal_choice_not_allowed"} =
             ctx.conn
             |> authed(ctx.member)
             |> put("#{me(ctx)}/subscriptions/#{other.id}/auto-renew", %{auto_renew: false})
             |> json_response(422)

    assert %{"code" => "invalid_auto_renew"} =
             ctx.conn
             |> authed(ctx.member)
             |> put("#{me(ctx)}/subscriptions/#{ctx.subscription.id}/auto-renew", %{
               auto_renew: "nope"
             })
             |> json_response(422)
  end

  test "another member's subscription is not found", ctx do
    stranger = user_fixture()
    add!(ctx.box, stranger, [:member])

    ctx.conn
    |> authed(stranger)
    |> put("#{me(ctx)}/subscriptions/#{ctx.subscription.id}/auto-renew", %{auto_renew: false})
    |> json_response(404)
  end

  defp add!(organization, user, roles) do
    {:ok, _membership} =
      Organizations.add_membership(%{
        organization_id: organization.id,
        user_id: user.id,
        role: hd(roles),
        roles: roles,
        status: :active,
        joined_at: DateTime.utc_now()
      })
  end
end
