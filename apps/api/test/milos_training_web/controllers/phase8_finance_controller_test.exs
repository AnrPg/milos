defmodule MilosTrainingWeb.Phase8FinanceControllerTest do
  use MilosTrainingWeb.ConnCase, async: false

  alias MilosTraining.{Finance, Organizations}

  import MilosTraining.TestFixtures

  test "receipt endpoint records money and returns the immediately paid document", %{conn: conn} do
    admin = admin_fixture(%{nickname: "receipt_admin"})
    member = user_fixture(%{role: :member, nickname: "receipt_member"})
    {organization, context} = tenant_fixture(admin, "Receipt Tenant")
    add_tenant_member(organization, member, :member)

    assert {:ok, package} =
             Finance.create_package(context, %{
               name: "Receipt package",
               family: "unlimited",
               billing_period: "monthly",
               base_price_cents: 5_000
             })

    assert {:ok, membership} =
             Finance.upsert_membership(context, member.id, %{
               user_type_snapshot: "member",
               status: "active",
               signup_source: "admin_created"
             })

    assert {:ok, subscription} = Finance.assign_package(context, membership.id, package.id, %{})

    response =
      conn
      |> put_bearer_token(admin)
      |> post(
        "/api/org/#{organization.slug}/admin/finance/members/#{member.id}/receipts",
        %{
          amount_cents: 5_000,
          payment_method: "cash",
          paid_on: Date.to_iso8601(Date.utc_today()),
          description: "Monthly membership",
          membership_package_subscription_id: subscription.id,
          idempotency_key: Ecto.UUID.generate()
        }
      )
      |> json_response(201)

    assert response["receipt"]["document_type"] == "receipt"
    assert response["receipt"]["amount_cents"] == 5_000
    assert response["receipt"]["invoice"]["status"] == "paid"
    assert response["receipt"]["invoice"]["balance_due_cents"] == 0
    assert response["receipt"]["invoice"]["membership_package_subscription_id"] == subscription.id
    assert response["receipt"]["package_name"] == "Receipt package"
    assert response["receipt"]["payment"]["membership_package_subscription_id"] == subscription.id

    assert response["receipt"]["payment"]["finance_invoice_id"] ==
             response["receipt"]["invoice"]["id"]
  end

  test "retiring a package atomically reconciles effective subscribers by role", %{conn: conn} do
    admin = admin_fixture()
    member = user_fixture(%{role: :member, nickname: "retired_plan_member"})
    athlete = user_fixture(%{role: :athlete, nickname: "retired_plan_athlete"})
    {organization, context} = tenant_fixture(admin, "Retire Tenant")
    add_tenant_member(organization, member, :member)
    add_tenant_member(organization, athlete, :athlete)

    {:ok, source} =
      Finance.create_package(context, %{
        code: "retiring-source",
        name: "Retiring source",
        family: "hybrid",
        billing_period: "monthly",
        base_price_cents: 8_000
      })

    {:ok, member_replacement} =
      Finance.create_package(context, %{
        code: "member-replacement",
        name: "Member replacement",
        family: "unlimited",
        billing_period: "monthly",
        base_price_cents: 6_000
      })

    {:ok, athlete_replacement} =
      Finance.create_package(context, %{
        code: "athlete-replacement",
        name: "Athlete replacement",
        family: "personal-programming",
        billing_period: "monthly",
        base_price_cents: 10_000
      })

    {:ok, member_membership} =
      Finance.upsert_membership(context, member.id, %{
        user_type_snapshot: "member",
        status: "active",
        signup_source: "admin_created"
      })

    {:ok, athlete_membership} =
      Finance.upsert_membership(context, athlete.id, %{
        user_type_snapshot: "athlete",
        status: "active",
        signup_source: "admin_created"
      })

    {:ok, _} = Finance.assign_package(context, member_membership.id, source.id, %{})
    {:ok, _} = Finance.assign_package(context, athlete_membership.id, source.id, %{})

    blocked_response =
      conn
      |> put_bearer_token(admin)
      |> patch(
        "/api/org/#{organization.slug}/admin/finance/packages/#{source.id}",
        %{active: false}
      )
      |> json_response(409)

    assert blocked_response["error"] =~ "reconciliation"

    response =
      conn
      |> recycle()
      |> put_bearer_token(admin)
      |> patch(
        "/api/org/#{organization.slug}/admin/finance/packages/#{source.id}/retire",
        %{
          replacement_package_by_role: %{
            member: member_replacement.id,
            athlete: athlete_replacement.id
          }
        }
      )
      |> json_response(200)

    assert response["package"]["active"] == false
    assert response["reassigned_count"] == 2

    assert Finance.get_member_profile(context, member.id).active_package_subscription.membership_package_id ==
             member_replacement.id

    assert Finance.get_member_profile(context, athlete.id).active_package_subscription.membership_package_id ==
             athlete_replacement.id
  end

  test "admin can manage package, membership, promo code, redemption, and search slices", %{
    conn: conn
  } do
    admin = admin_fixture()
    member = user_fixture(%{role: :member, nickname: "finance_member"})
    {organization, _context} = tenant_fixture(admin, "Manage Slices Tenant")
    add_tenant_member(organization, member, :member)

    package_response =
      conn
      |> put_bearer_token(admin)
      |> post(
        "/api/org/#{organization.slug}/admin/finance/packages",
        %{
          code: "controller hybrid",
          name: "Controller Hybrid",
          family: "hybrid",
          billing_period: "monthly",
          base_price_cents: 9900
        }
      )
      |> json_response(201)

    package_id = package_response["package"]["id"]
    assert package_response["package"]["code"] == "controller_hybrid"

    package_detail_response =
      conn
      |> recycle()
      |> put_bearer_token(admin)
      |> get("/api/org/#{organization.slug}/admin/finance/packages/#{package_id}")
      |> json_response(200)

    assert package_detail_response["package"]["id"] == package_id

    membership_response =
      conn
      |> recycle()
      |> put_bearer_token(admin)
      |> patch(
        "/api/org/#{organization.slug}/admin/finance/members/#{member.id}",
        %{
          user_type_snapshot: "member",
          status: "active",
          signup_source: "admin_created"
        }
      )
      |> json_response(200)

    assert membership_response["membership"]["status"] == "active"

    conn
    |> recycle()
    |> put_bearer_token(admin)
    |> post(
      "/api/org/#{organization.slug}/admin/finance/members/#{member.id}/packages",
      %{
        membership_package_id: package_id
      }
    )
    |> json_response(201)

    campaign_response =
      conn
      |> recycle()
      |> put_bearer_token(admin)
      |> post(
        "/api/org/#{organization.slug}/admin/finance/promotions",
        %{name: "Controller Campaign"}
      )
      |> json_response(201)

    campaign_id = campaign_response["promotion_campaign"]["id"]

    code_response =
      conn
      |> recycle()
      |> put_bearer_token(admin)
      |> post(
        "/api/org/#{organization.slug}/admin/finance/promotions/#{campaign_id}/codes",
        %{
          code: "controller 10",
          discount_type: "percent",
          discount_value: 10
        }
      )
      |> json_response(201)

    assert code_response["promotion_code"]["code"] == "CONTROLLER-10"

    redemption_response =
      conn
      |> recycle()
      |> put_bearer_token(admin)
      |> post(
        "/api/org/#{organization.slug}/admin/finance/members/#{member.id}/promotion-redemptions",
        %{
          promotion_code: "CONTROLLER-10"
        }
      )
      |> json_response(201)

    assert redemption_response["promotion_redemption"]["discount_value_snapshot"] == 10

    payment_response =
      conn
      |> recycle()
      |> put_bearer_token(admin)
      |> post(
        "/api/org/#{organization.slug}/admin/finance/members/#{member.id}/payments",
        %{
          amount_cents: 9900,
          payment_method: "cash",
          payment_status: "pending"
        }
      )
      |> json_response(201)

    credit_response =
      conn
      |> recycle()
      |> put_bearer_token(admin)
      |> post(
        "/api/org/#{organization.slug}/admin/finance/members/#{member.id}/credits",
        %{
          amount_cents: 2500,
          description: "Controller goodwill credit",
          request_id: Ecto.UUID.generate()
        }
      )
      |> json_response(201)

    assert credit_response["credit_ledger_entry"]["amount_cents"] == 2500

    application_response =
      conn
      |> recycle()
      |> put_bearer_token(admin)
      |> post(
        "/api/org/#{organization.slug}/admin/finance/members/#{member.id}/payments/#{payment_response["payment"]["id"]}/credits",
        %{
          amount_cents: 1000,
          description: "Controller payment credit",
          request_id: Ecto.UUID.generate()
        }
      )
      |> json_response(201)

    assert application_response["credit_ledger_entry"]["amount_cents"] == -1000

    invoice_response =
      conn
      |> recycle()
      |> put_bearer_token(admin)
      |> post(
        "/api/org/#{organization.slug}/admin/finance/members/#{member.id}/invoices",
        %{
          amount_cents: 9900,
          description: "Controller invoice",
          due_date: Date.to_iso8601(Date.add(Date.utc_today(), 7))
        }
      )
      |> json_response(201)

    assert invoice_response["invoice"]["status"] == "draft"
    invoice_id = invoice_response["invoice"]["id"]

    issued_response =
      conn
      |> recycle()
      |> put_bearer_token(admin)
      |> patch(
        "/api/org/#{organization.slug}/admin/finance/invoices/#{invoice_id}/issue",
        %{}
      )
      |> json_response(200)

    assert issued_response["invoice"]["status"] == "issued"

    invoice_credit_response =
      conn
      |> recycle()
      |> put_bearer_token(admin)
      |> post(
        "/api/org/#{organization.slug}/admin/finance/members/#{member.id}/invoices/#{invoice_id}/credits",
        %{
          amount_cents: 1000,
          description: "Controller invoice credit",
          request_id: Ecto.UUID.generate()
        }
      )
      |> json_response(201)

    assert invoice_credit_response["credit_ledger_entry"]["finance_invoice_id"] == invoice_id

    invoice_payment_response =
      conn
      |> recycle()
      |> put_bearer_token(admin)
      |> post(
        "/api/org/#{organization.slug}/admin/finance/members/#{member.id}/payments",
        %{
          finance_invoice_id: invoice_id,
          amount_cents: 8900,
          payment_method: "cash",
          payment_status: "paid"
        }
      )
      |> json_response(201)

    assert invoice_payment_response["payment"]["finance_invoice_id"] == invoice_id

    payment_reversal_response =
      conn
      |> recycle()
      |> put_bearer_token(admin)
      |> post(
        "/api/org/#{organization.slug}/admin/finance/members/#{member.id}/payments/#{invoice_payment_response["payment"]["id"]}/reversals",
        %{
          amount_cents: 8900,
          reason: "Controller refund",
          request_id: Ecto.UUID.generate()
        }
      )
      |> json_response(201)

    assert payment_reversal_response["payment_reversal"]["finance_invoice_id"] == invoice_id
    assert payment_reversal_response["payment_reversal"]["amount_cents"] == 8900

    credit_reversal_response =
      conn
      |> recycle()
      |> put_bearer_token(admin)
      |> post(
        "/api/org/#{organization.slug}/admin/finance/members/#{member.id}/credits/#{invoice_credit_response["credit_ledger_entry"]["id"]}/reversals",
        %{
          amount_cents: 1000,
          reason: "Controller credit restoration",
          request_id: Ecto.UUID.generate()
        }
      )
      |> json_response(201)

    assert credit_reversal_response["credit_ledger_entry"]["amount_cents"] == 1000

    profile_after_reversals =
      conn
      |> recycle()
      |> put_bearer_token(admin)
      |> get("/api/org/#{organization.slug}/admin/finance/members/#{member.id}")
      |> json_response(200)

    assert profile_after_reversals["drill_down"]["identity"]["nickname"] == "finance_member"
    assert profile_after_reversals["drill_down"]["current_status"]["state"] == "active"
    assert profile_after_reversals["drill_down"]["package_relationship"]["status"] == "active"
    assert is_list(profile_after_reversals["drill_down"]["financial_timeline"])

    action_keys =
      Enum.map(profile_after_reversals["drill_down"]["actions"], & &1["key"])

    assert "update_membership" in action_keys
    assert "renew_membership" in action_keys
    assert "record_payment" in action_keys

    reopened_invoice =
      Enum.find(profile_after_reversals["invoices"], &(&1["id"] == invoice_id))

    assert reopened_invoice["balance_due_cents"] == 9900
    assert profile_after_reversals["credit_balance"] == 1500

    renewal_response =
      conn
      |> recycle()
      |> put_bearer_token(admin)
      |> post(
        "/api/org/#{organization.slug}/admin/finance/members/#{member.id}/invoices/renewal",
        %{
          service_period_start: Date.to_iso8601(Date.utc_today())
        }
      )
      |> json_response(201)

    assert renewal_response["invoice"]["invoice_type"] == "renewal"

    queue_response =
      conn
      |> recycle()
      |> put_bearer_token(admin)
      |> get(
        "/api/org/#{organization.slug}/admin/finance/queues",
        %{limit: 10}
      )
      |> json_response(200)

    assert length(queue_response["queues"]["pending_payments"]) >= 1
    assert length(queue_response["queues"]["promotion_redemptions"]) >= 1
    assert is_list(queue_response["queues"]["overdue_invoices"])

    search_response =
      conn
      |> recycle()
      |> put_bearer_token(admin)
      |> get("/api/org/#{organization.slug}/admin/search", %{
        role: "all",
        membership_status: "active",
        package_code: "controller_hybrid"
      })
      |> json_response(200)

    assert Enum.map(search_response["users"], & &1["id"]) == [member.id]
    assert search_response["meta"]["search_backend"] in ["meilisearch", "postgres_fallback"]
  end

  test "assigning a package creates a finance membership for an unmanaged user", %{conn: conn} do
    admin = admin_fixture()
    member = user_fixture(%{role: :member, nickname: "unmanaged_package_member"})
    {organization, context} = tenant_fixture(admin, "Unmanaged Package Tenant")
    add_tenant_member(organization, member, :member)

    assert Finance.get_member_profile(context, member.id) == nil

    {:ok, package} =
      Finance.create_package(context, %{
        code: "unmanaged_member_package",
        name: "Unmanaged Member Package",
        family: "unlimited",
        billing_period: "monthly",
        base_price_cents: 7500
      })

    response =
      conn
      |> put_bearer_token(admin)
      |> post(
        "/api/org/#{organization.slug}/admin/finance/members/#{member.id}/packages",
        %{
          membership_package_id: package.id
        }
      )
      |> json_response(201)

    profile = Finance.get_member_profile(context, member.id)

    assert profile.membership.user_type_snapshot == "member"
    assert profile.membership.status == "trial"
    assert profile.membership.signup_source == "admin_created"
    assert response["package_subscription"]["membership_id"] == profile.membership.id
    assert response["package_subscription"]["membership_package_id"] == package.id
  end

  test "admin can create referral rewards", %{conn: conn} do
    admin = admin_fixture()
    referrer = user_fixture(%{role: :member})
    referred = user_fixture(%{role: :athlete})
    {organization, context} = tenant_fixture(admin, "Referral Rewards Tenant")
    add_tenant_member(organization, referrer, :member)
    add_tenant_member(organization, referred, :athlete)

    {:ok, _referrer_membership} =
      Finance.upsert_membership(context, referrer.id, %{
        user_type_snapshot: "member",
        status: "active",
        signup_source: "direct"
      })

    {:ok, membership} =
      Finance.upsert_membership(context, referred.id, %{
        user_type_snapshot: "athlete",
        status: "trial",
        signup_source: "referral"
      })

    program_response =
      conn
      |> put_bearer_token(admin)
      |> post(
        "/api/org/#{organization.slug}/admin/finance/referral-programs",
        %{
          name: "Controller referrals",
          reward_type: "credit",
          reward_value: 1500,
          active: true
        }
      )
      |> json_response(201)

    program_id = program_response["referral_program"]["id"]

    programs_response =
      conn
      |> recycle()
      |> put_bearer_token(admin)
      |> get("/api/org/#{organization.slug}/admin/finance/referral-programs")
      |> json_response(200)

    assert Enum.any?(programs_response["referral_programs"], &(&1["id"] == program_id))

    updated_program_response =
      conn
      |> recycle()
      |> put_bearer_token(admin)
      |> patch(
        "/api/org/#{organization.slug}/admin/finance/referral-programs/#{program_id}",
        %{
          name: "Controller referrals updated",
          reward_type: "credit",
          reward_value: 1750,
          active: true
        }
      )
      |> json_response(200)

    assert updated_program_response["referral_program"]["name"] == "Controller referrals updated"
    assert updated_program_response["referral_program"]["reward_value"] == 1750

    event_response =
      conn
      |> recycle()
      |> put_bearer_token(admin)
      |> post(
        "/api/org/#{organization.slug}/admin/finance/referrals",
        %{
          referral_program_id: program_id,
          referrer_user_id: referrer.id,
          referred_user_id: referred.id,
          membership_id: membership.id
        }
      )
      |> json_response(201)

    early_reward_response =
      conn
      |> recycle()
      |> put_bearer_token(admin)
      |> post(
        "/api/org/#{organization.slug}/admin/finance/referrals/#{event_response["referral_event"]["id"]}/rewards",
        %{}
      )
      |> json_response(409)

    assert early_reward_response["error"] ==
             "Referral event must be approved before applying rewards"

    event_status_response =
      conn
      |> recycle()
      |> put_bearer_token(admin)
      |> patch(
        "/api/org/#{organization.slug}/admin/finance/referrals/#{event_response["referral_event"]["id"]}/status",
        %{
          status: "approved"
        }
      )
      |> json_response(200)

    assert event_status_response["referral_event"]["status"] == "approved"

    referrals_response =
      conn
      |> recycle()
      |> put_bearer_token(admin)
      |> get("/api/org/#{organization.slug}/admin/finance/referrals")
      |> json_response(200)

    listed_event =
      Enum.find(
        referrals_response["referral_events"],
        &(&1["id"] == event_response["referral_event"]["id"])
      )

    assert listed_event["program_name"] == "Controller referrals updated"
    assert listed_event["referrer_nickname"] == referrer.nickname
    assert listed_event["referred_nickname"] == referred.nickname

    reward_response =
      conn
      |> recycle()
      |> put_bearer_token(admin)
      |> post(
        "/api/org/#{organization.slug}/admin/finance/referrals/#{event_response["referral_event"]["id"]}/rewards",
        %{}
      )
      |> json_response(201)

    assert reward_response["referral_reward"]["recipient_user_id"] == referrer.id
    assert reward_response["referral_reward"]["reward_value"] == 1750

    duplicate_response =
      conn
      |> recycle()
      |> put_bearer_token(admin)
      |> post(
        "/api/org/#{organization.slug}/admin/finance/referrals/#{event_response["referral_event"]["id"]}/rewards",
        %{}
      )
      |> json_response(409)

    assert duplicate_response["error"] == "Referral reward already exists for this event"

    approved_response =
      conn
      |> recycle()
      |> put_bearer_token(admin)
      |> patch(
        "/api/org/#{organization.slug}/admin/finance/referral-rewards/#{reward_response["referral_reward"]["id"]}/status",
        %{
          status: "approved"
        }
      )
      |> json_response(200)

    assert approved_response["referral_reward"]["status"] == "approved"

    applied_response =
      conn
      |> recycle()
      |> put_bearer_token(admin)
      |> patch(
        "/api/org/#{organization.slug}/admin/finance/referral-rewards/#{reward_response["referral_reward"]["id"]}/status",
        %{
          status: "applied"
        }
      )
      |> json_response(200)

    assert applied_response["referral_reward"]["status"] == "applied"

    rewards_response =
      conn
      |> recycle()
      |> put_bearer_token(admin)
      |> get("/api/org/#{organization.slug}/admin/finance/referral-rewards")
      |> json_response(200)

    listed_reward =
      Enum.find(
        rewards_response["referral_rewards"],
        &(&1["id"] == reward_response["referral_reward"]["id"])
      )

    assert listed_reward["recipient_nickname"] == referrer.nickname
    assert listed_reward["referral_label"] == "#{referrer.nickname} -> #{referred.nickname}"

    profile_response =
      conn
      |> recycle()
      |> put_bearer_token(admin)
      |> get("/api/org/#{organization.slug}/admin/finance/members/#{referrer.id}")
      |> json_response(200)

    assert profile_response["credit_balance"] == 1750
    assert [credit_entry] = profile_response["credit_ledger_entries"]
    assert credit_entry["referral_reward_id"] == reward_response["referral_reward"]["id"]

    members_response =
      conn
      |> recycle()
      |> put_bearer_token(admin)
      |> get("/api/org/#{organization.slug}/admin/finance/members")
      |> json_response(200)

    referrer_row =
      Enum.find(members_response["members"], &(&1["id"] == referrer.id))

    assert referrer_row["credit_balance"] == 1750
    assert referrer_row["credit_balance_cents"] == 1750
  end

  test "admin finance package and referral actions stay inside the selected org", %{conn: conn} do
    admin_a = admin_fixture(%{nickname: "finance_tenant_admin_a"})
    admin_b = admin_fixture(%{nickname: "finance_tenant_admin_b"})
    referrer = user_fixture(%{role: :member, nickname: "finance_tenant_referrer"})
    referred = user_fixture(%{role: :member, nickname: "finance_tenant_referred"})

    {_org_a, context_a} = tenant_fixture(admin_a, "Finance Tenant A")
    {_org_b, context_b} = tenant_fixture(admin_b, "Finance Tenant B")
    add_tenant_member(context_a.organization, referrer, :member)
    add_tenant_member(context_b.organization, referrer, :member)
    add_tenant_member(context_b.organization, referred, :member)

    {:ok, package_a} = Finance.create_package(context_a, package_params("finance_tenant_a"))
    {:ok, replacement_b} = Finance.create_package(context_b, package_params("finance_tenant_b"))

    {:ok, referrer_membership_a} =
      Finance.upsert_membership(context_a, referrer.id, finance_membership_params())

    {:ok, referrer_membership_b} =
      Finance.upsert_membership(context_b, referrer.id, finance_membership_params())

    {:ok, referred_membership_b} =
      Finance.upsert_membership(context_b, referred.id, finance_membership_params())

    {:ok, _subscription_a} =
      Finance.assign_package(context_a, referrer_membership_a.id, package_a.id, %{
        starts_on: Date.utc_today()
      })

    {:ok, program_b} =
      Finance.create_referral_program(context_b, %{
        name: "Tenant B referrals",
        reward_type: "credit",
        reward_value: 750,
        active: true
      })

    {:ok, event_b} =
      Finance.create_referral_event(context_b, %{
        referral_program_id: program_b.id,
        referrer_user_id: referrer.id,
        referred_user_id: referred.id,
        membership_id: referred_membership_b.id,
        referrer_role_snapshot: "member",
        referred_role_snapshot: "member",
        status: "approved"
      })

    {:ok, reward_b} = Finance.create_referral_reward(context_b, event_b.id, %{})

    update_foreign_package =
      conn
      |> put_bearer_token(admin_a)
      |> patch(
        "/api/org/#{context_a.organization.slug}/admin/finance/packages/#{replacement_b.id}",
        %{
          name: "Cross tenant rename"
        }
      )
      |> json_response(404)

    assert update_foreign_package["code"] == "not_found"

    retire_with_foreign_replacement =
      build_conn()
      |> put_bearer_token(admin_a)
      |> patch(
        "/api/org/#{context_a.organization.slug}/admin/finance/packages/#{package_a.id}/retire",
        %{
          replacement_package_by_role: %{member: replacement_b.id}
        }
      )
      |> json_response(422)

    assert retire_with_foreign_replacement["code"] == "invalid_package_replacement"

    referrals_a =
      build_conn()
      |> put_bearer_token(admin_a)
      |> get("/api/org/#{context_a.organization.slug}/admin/finance/referrals")
      |> json_response(200)

    refute Enum.any?(referrals_a["referral_events"], &(&1["id"] == event_b.id))

    rewards_a =
      build_conn()
      |> put_bearer_token(admin_a)
      |> get("/api/org/#{context_a.organization.slug}/admin/finance/referral-rewards")
      |> json_response(200)

    refute Enum.any?(rewards_a["referral_rewards"], &(&1["id"] == reward_b.id))

    applied_b =
      build_conn()
      |> put_bearer_token(admin_b)
      |> patch(
        "/api/org/#{context_b.organization.slug}/admin/finance/referral-rewards/#{reward_b.id}/status",
        %{
          status: "applied"
        }
      )
      |> json_response(200)

    assert applied_b["referral_reward"]["status"] == "applied"
    assert Finance.get_member_profile(context_a, referrer.id).credit_balance == 0
    assert Finance.get_member_profile(context_b, referrer.id).credit_balance == 750
    assert referrer_membership_b.id != referrer_membership_a.id
  end

  defp tenant_fixture(user, name) do
    {:ok, organization} =
      Organizations.create_organization(%{
        name: "#{name} #{System.unique_integer([:positive])}"
      })

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

  defp finance_membership_params do
    %{
      user_type_snapshot: "member",
      status: "active",
      signup_source: "admin_created"
    }
  end

  defp package_params(code) do
    %{
      code: code,
      name: code,
      family: "limited-visits",
      billing_period: "monthly",
      params: %{
        "entitlement_version" => 1,
        "channels" => ["in_person"],
        "capabilities" => ["book_classes"],
        "allowances" => %{"class_visits" => %{"limit" => 4, "period" => "calendar_month"}}
      }
    }
  end
end
