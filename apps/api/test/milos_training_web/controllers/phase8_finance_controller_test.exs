defmodule MilosTrainingWeb.Phase8FinanceControllerTest do
  use MilosTrainingWeb.ConnCase, async: false

  alias MilosTraining.Finance

  import MilosTraining.TestFixtures

  test "retiring a package atomically reconciles effective subscribers by role", %{conn: conn} do
    admin = admin_fixture()
    member = user_fixture(%{role: :member, nickname: "retired_plan_member"})
    athlete = user_fixture(%{role: :athlete, nickname: "retired_plan_athlete"})

    {:ok, source} =
      Finance.create_package(%{
        code: "retiring-source",
        name: "Retiring source",
        family: "hybrid",
        billing_period: "monthly",
        base_price_cents: 8_000
      })

    {:ok, member_replacement} =
      Finance.create_package(%{
        code: "member-replacement",
        name: "Member replacement",
        family: "unlimited",
        billing_period: "monthly",
        base_price_cents: 6_000
      })

    {:ok, athlete_replacement} =
      Finance.create_package(%{
        code: "athlete-replacement",
        name: "Athlete replacement",
        family: "personal-programming",
        billing_period: "monthly",
        base_price_cents: 10_000
      })

    {:ok, member_membership} =
      Finance.upsert_membership(member.id, %{
        user_type_snapshot: "member",
        status: "active",
        signup_source: "admin_created"
      })

    {:ok, athlete_membership} =
      Finance.upsert_membership(athlete.id, %{
        user_type_snapshot: "athlete",
        status: "active",
        signup_source: "admin_created"
      })

    {:ok, _} = Finance.assign_package(member_membership.id, source.id, %{})
    {:ok, _} = Finance.assign_package(athlete_membership.id, source.id, %{})

    blocked_response =
      conn
      |> put_bearer_token(admin)
      |> patch("/api/admin/finance/packages/#{source.id}", %{active: false})
      |> json_response(409)

    assert blocked_response["error"] =~ "reconciliation"

    response =
      conn
      |> recycle()
      |> put_bearer_token(admin)
      |> patch("/api/admin/finance/packages/#{source.id}/retire", %{
        replacement_package_by_role: %{
          member: member_replacement.id,
          athlete: athlete_replacement.id
        }
      })
      |> json_response(200)

    assert response["package"]["active"] == false
    assert response["reassigned_count"] == 2

    assert Finance.get_member_profile(member.id).active_package_subscription.membership_package_id ==
             member_replacement.id

    assert Finance.get_member_profile(athlete.id).active_package_subscription.membership_package_id ==
             athlete_replacement.id
  end

  test "admin can manage package, membership, promo code, redemption, and search slices", %{
    conn: conn
  } do
    admin = admin_fixture()
    member = user_fixture(%{role: :member, nickname: "finance_member"})

    package_response =
      conn
      |> put_bearer_token(admin)
      |> post("/api/admin/finance/packages", %{
        code: "controller hybrid",
        name: "Controller Hybrid",
        family: "hybrid",
        billing_period: "monthly",
        base_price_cents: 9900
      })
      |> json_response(201)

    package_id = package_response["package"]["id"]
    assert package_response["package"]["code"] == "controller_hybrid"

    package_detail_response =
      conn
      |> recycle()
      |> put_bearer_token(admin)
      |> get("/api/admin/finance/packages/#{package_id}")
      |> json_response(200)

    assert package_detail_response["package"]["id"] == package_id

    membership_response =
      conn
      |> recycle()
      |> put_bearer_token(admin)
      |> patch("/api/admin/finance/members/#{member.id}", %{
        user_type_snapshot: "member",
        status: "active",
        signup_source: "admin_created"
      })
      |> json_response(200)

    assert membership_response["membership"]["status"] == "active"

    conn
    |> recycle()
    |> put_bearer_token(admin)
    |> post("/api/admin/finance/members/#{member.id}/packages", %{
      membership_package_id: package_id
    })
    |> json_response(201)

    campaign_response =
      conn
      |> recycle()
      |> put_bearer_token(admin)
      |> post("/api/admin/finance/promotions", %{name: "Controller Campaign"})
      |> json_response(201)

    campaign_id = campaign_response["promotion_campaign"]["id"]

    code_response =
      conn
      |> recycle()
      |> put_bearer_token(admin)
      |> post("/api/admin/finance/promotions/#{campaign_id}/codes", %{
        code: "controller 10",
        discount_type: "percent",
        discount_value: 10
      })
      |> json_response(201)

    assert code_response["promotion_code"]["code"] == "CONTROLLER-10"

    redemption_response =
      conn
      |> recycle()
      |> put_bearer_token(admin)
      |> post("/api/admin/finance/members/#{member.id}/promotion-redemptions", %{
        promotion_code: "CONTROLLER-10"
      })
      |> json_response(201)

    assert redemption_response["promotion_redemption"]["discount_value_snapshot"] == 10

    payment_response =
      conn
      |> recycle()
      |> put_bearer_token(admin)
      |> post("/api/admin/finance/members/#{member.id}/payments", %{
        amount_cents: 9900,
        payment_method: "cash",
        payment_status: "pending"
      })
      |> json_response(201)

    credit_response =
      conn
      |> recycle()
      |> put_bearer_token(admin)
      |> post("/api/admin/finance/members/#{member.id}/credits", %{
        amount_cents: 2500,
        description: "Controller goodwill credit"
      })
      |> json_response(201)

    assert credit_response["credit_ledger_entry"]["amount_cents"] == 2500

    application_response =
      conn
      |> recycle()
      |> put_bearer_token(admin)
      |> post(
        "/api/admin/finance/members/#{member.id}/payments/#{payment_response["payment"]["id"]}/credits",
        %{
          amount_cents: 1000,
          description: "Controller payment credit"
        }
      )
      |> json_response(201)

    assert application_response["credit_ledger_entry"]["amount_cents"] == -1000

    invoice_response =
      conn
      |> recycle()
      |> put_bearer_token(admin)
      |> post("/api/admin/finance/members/#{member.id}/invoices", %{
        amount_cents: 9900,
        description: "Controller invoice",
        due_date: Date.to_iso8601(Date.add(Date.utc_today(), 7))
      })
      |> json_response(201)

    assert invoice_response["invoice"]["status"] == "draft"
    invoice_id = invoice_response["invoice"]["id"]

    issued_response =
      conn
      |> recycle()
      |> put_bearer_token(admin)
      |> patch("/api/admin/finance/invoices/#{invoice_id}/issue", %{})
      |> json_response(200)

    assert issued_response["invoice"]["status"] == "issued"

    invoice_credit_response =
      conn
      |> recycle()
      |> put_bearer_token(admin)
      |> post("/api/admin/finance/members/#{member.id}/invoices/#{invoice_id}/credits", %{
        amount_cents: 1000,
        description: "Controller invoice credit"
      })
      |> json_response(201)

    assert invoice_credit_response["credit_ledger_entry"]["finance_invoice_id"] == invoice_id

    invoice_payment_response =
      conn
      |> recycle()
      |> put_bearer_token(admin)
      |> post("/api/admin/finance/members/#{member.id}/payments", %{
        finance_invoice_id: invoice_id,
        amount_cents: 8900,
        payment_method: "cash",
        payment_status: "paid"
      })
      |> json_response(201)

    assert invoice_payment_response["payment"]["finance_invoice_id"] == invoice_id

    payment_reversal_response =
      conn
      |> recycle()
      |> put_bearer_token(admin)
      |> post(
        "/api/admin/finance/members/#{member.id}/payments/#{invoice_payment_response["payment"]["id"]}/reversals",
        %{
          amount_cents: 8900,
          reason: "Controller refund"
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
        "/api/admin/finance/members/#{member.id}/credits/#{invoice_credit_response["credit_ledger_entry"]["id"]}/reversals",
        %{
          amount_cents: 1000,
          reason: "Controller credit restoration"
        }
      )
      |> json_response(201)

    assert credit_reversal_response["credit_ledger_entry"]["amount_cents"] == 1000

    profile_after_reversals =
      conn
      |> recycle()
      |> put_bearer_token(admin)
      |> get("/api/admin/finance/members/#{member.id}")
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
      |> post("/api/admin/finance/members/#{member.id}/invoices/renewal", %{
        service_period_start: Date.to_iso8601(Date.utc_today())
      })
      |> json_response(201)

    assert renewal_response["invoice"]["invoice_type"] == "renewal"

    queue_response =
      conn
      |> recycle()
      |> put_bearer_token(admin)
      |> get("/api/admin/finance/queues", %{limit: 10})
      |> json_response(200)

    assert length(queue_response["queues"]["pending_payments"]) >= 1
    assert length(queue_response["queues"]["promotion_redemptions"]) >= 1
    assert is_list(queue_response["queues"]["overdue_invoices"])

    search_response =
      conn
      |> recycle()
      |> put_bearer_token(admin)
      |> get("/api/admin/search", %{
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

    assert Finance.get_member_profile(member.id) == nil

    {:ok, package} =
      Finance.create_package(%{
        code: "unmanaged_member_package",
        name: "Unmanaged Member Package",
        family: "unlimited",
        billing_period: "monthly",
        base_price_cents: 7500
      })

    response =
      conn
      |> put_bearer_token(admin)
      |> post("/api/admin/finance/members/#{member.id}/packages", %{
        membership_package_id: package.id
      })
      |> json_response(201)

    profile = Finance.get_member_profile(member.id)

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

    {:ok, _referrer_membership} =
      Finance.upsert_membership(referrer.id, %{
        user_type_snapshot: "member",
        status: "active",
        signup_source: "direct"
      })

    {:ok, membership} =
      Finance.upsert_membership(referred.id, %{
        user_type_snapshot: "athlete",
        status: "trial",
        signup_source: "referral"
      })

    program_response =
      conn
      |> put_bearer_token(admin)
      |> post("/api/admin/finance/referral-programs", %{
        name: "Controller referrals",
        reward_type: "credit",
        reward_value: 1500,
        active: true
      })
      |> json_response(201)

    program_id = program_response["referral_program"]["id"]

    programs_response =
      conn
      |> recycle()
      |> put_bearer_token(admin)
      |> get("/api/admin/finance/referral-programs")
      |> json_response(200)

    assert Enum.any?(programs_response["referral_programs"], &(&1["id"] == program_id))

    updated_program_response =
      conn
      |> recycle()
      |> put_bearer_token(admin)
      |> patch("/api/admin/finance/referral-programs/#{program_id}", %{
        name: "Controller referrals updated",
        reward_type: "credit",
        reward_value: 1750,
        active: true
      })
      |> json_response(200)

    assert updated_program_response["referral_program"]["name"] == "Controller referrals updated"
    assert updated_program_response["referral_program"]["reward_value"] == 1750

    event_response =
      conn
      |> recycle()
      |> put_bearer_token(admin)
      |> post("/api/admin/finance/referrals", %{
        referral_program_id: program_id,
        referrer_user_id: referrer.id,
        referred_user_id: referred.id,
        membership_id: membership.id
      })
      |> json_response(201)

    early_reward_response =
      conn
      |> recycle()
      |> put_bearer_token(admin)
      |> post(
        "/api/admin/finance/referrals/#{event_response["referral_event"]["id"]}/rewards",
        %{}
      )
      |> json_response(409)

    assert early_reward_response["error"] ==
             "Referral event must be approved before applying rewards"

    event_status_response =
      conn
      |> recycle()
      |> put_bearer_token(admin)
      |> patch("/api/admin/finance/referrals/#{event_response["referral_event"]["id"]}/status", %{
        status: "approved"
      })
      |> json_response(200)

    assert event_status_response["referral_event"]["status"] == "approved"

    referrals_response =
      conn
      |> recycle()
      |> put_bearer_token(admin)
      |> get("/api/admin/finance/referrals")
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
        "/api/admin/finance/referrals/#{event_response["referral_event"]["id"]}/rewards",
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
        "/api/admin/finance/referrals/#{event_response["referral_event"]["id"]}/rewards",
        %{}
      )
      |> json_response(409)

    assert duplicate_response["error"] == "Referral reward already exists for this event"

    approved_response =
      conn
      |> recycle()
      |> put_bearer_token(admin)
      |> patch(
        "/api/admin/finance/referral-rewards/#{reward_response["referral_reward"]["id"]}/status",
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
        "/api/admin/finance/referral-rewards/#{reward_response["referral_reward"]["id"]}/status",
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
      |> get("/api/admin/finance/referral-rewards")
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
      |> get("/api/admin/finance/members/#{referrer.id}")
      |> json_response(200)

    assert profile_response["credit_balance"] == 1750
    assert [credit_entry] = profile_response["credit_ledger_entries"]
    assert credit_entry["referral_reward_id"] == reward_response["referral_reward"]["id"]

    members_response =
      conn
      |> recycle()
      |> put_bearer_token(admin)
      |> get("/api/admin/finance/members")
      |> json_response(200)

    referrer_row =
      Enum.find(members_response["members"], &(&1["id"] == referrer.id))

    assert referrer_row["credit_balance"] == 1750
    assert referrer_row["credit_balance_cents"] == 1750
  end
end
