defmodule PaleeWeb.PerksControllerTest do
  @moduledoc """
  ADR-191: a gym publishes partner perks with an open policy (a redemption
  method per perk, a benefit, rules and terms in versions); its clients
  claim them (the code, link or QR is revealed and recorded under the
  version they agreed to); the partner's counter verifies a personal QR
  with a signed, short-lived, single-use link; staff export the claims.
  """

  use PaleeWeb.ConnCase, async: false

  import Palee.TestFixtures
  import Palee.AnalyticsHelpers, only: [analytics_events: 2]

  alias Palee.{Facility, Finance, Organizations, Perks, Repo}
  alias Palee.Application.{MemberPerks, PerkPresenter, SignedToken}
  alias Palee.Identity.UserContext
  alias Palee.TestSupport.TelemetryCapture

  setup %{conn: conn} do
    {:ok, organization} =
      Organizations.create_organization(%{name: "Perk Gym #{System.unique_integer([:positive])}"})

    person = fn role ->
      user = user_fixture()

      {:ok, _membership} =
        Organizations.add_membership(%{
          organization_id: organization.id,
          user_id: user.id,
          role: role,
          status: :active,
          joined_at: DateTime.utc_now()
        })

      user
    end

    owner = person.(:owner)
    {:ok, owner_context} = Organizations.resolve_tenant_context(owner, organization.slug)

    %{
      organization: organization,
      owner: owner,
      owner_context: owner_context,
      person: person,
      first: person.(:member),
      second: person.(:member),
      coach: person.(:coach),
      as: fn user -> put_bearer_token(conn, user) end,
      admin: "/api/org/#{organization.slug}/admin"
    }
  end

  defp send_json(conn, method, path, body \\ %{}) do
    conn
    |> put_req_header("content-type", "application/json")
    |> dispatch(@endpoint, method, path, Jason.encode!(body))
  end

  defp perk_attrs(attrs) do
    Map.merge(
      %{
        partner_name: "SupplementsX",
        partner_url: "https://supplementsx.example",
        benefit: %{type: "percent", percent: 10},
        redemption: %{shared_code: "coach nikos"},
        terms: "Μία φορά ανά αγορά."
      },
      attrs
    )
  end

  defp create_perk!(ctx, attrs \\ %{}) do
    ctx.as.(ctx.owner)
    |> send_json(:post, "#{ctx.admin}/perks", perk_attrs(attrs))
    |> json_response(201)
    |> Map.fetch!("perk")
  end

  defp publish!(ctx, perk) do
    ctx.as.(ctx.owner)
    |> send_json(:post, "#{ctx.admin}/perks/#{perk["id"]}/publish")
    |> json_response(200)
    |> Map.fetch!("perk")
  end

  defp live!(ctx, attrs \\ %{}), do: ctx |> create_perk!(attrs) |> then(&publish!(ctx, &1))

  defp claim(ctx, user, perk),
    do: ctx.as.(user) |> send_json(:post, "/api/me/perks/#{perk["id"]}/claim")

  defp claim!(ctx, user, perk),
    do: claim(ctx, user, perk) |> json_response(200) |> Map.fetch!("claim")

  defp my_perks(ctx, user),
    do: ctx.as.(user) |> get("/api/me/perks") |> json_response(200) |> Map.fetch!("perks")

  defp staff_perk(ctx, perk),
    do:
      ctx.as.(ctx.owner)
      |> get("#{ctx.admin}/perks/#{perk["id"]}")
      |> json_response(200)
      |> Map.fetch!("perk")

  defp user_context(user), do: UserContext.new(user, %{})

  describe "the business" do
    test "creates a draft, publishes it and sees claim counts", ctx do
      TelemetryCapture.capture([[:palee, :perk, :published], [:palee, :perk, :claimed]])

      perk = create_perk!(ctx)
      assert perk["status"] == "draft"
      assert perk["redemption_method"] == "shared_code"
      assert perk["redemption"]["shared_code"] == "COACH-NIKOS"
      assert perk["benefit_label"] == "10%"
      assert perk["version"] == 1
      assert perk["rules"]["limits"]["max_per_member"] == 1
      assert my_perks(ctx, ctx.first) == []

      published = publish!(ctx, perk)
      assert published["status"] == "published"
      assert_receive {:telemetry_event, [:palee, :perk, :published], %{count: 1}, _meta}

      assert [%{"id" => id, "claimable" => true, "claim" => nil} = listed] =
               my_perks(ctx, ctx.first)

      assert id == perk["id"]
      refute Map.has_key?(listed, "redemption")
      refute inspect(listed) =~ "COACH-NIKOS"

      body = claim(ctx, ctx.first, perk) |> json_response(200)

      assert %{
               "created" => true,
               "claim" => %{"code" => "COACH-NIKOS", "status" => "claimed", "perk_version" => 1}
             } = body

      assert_receive {:telemetry_event, [:palee, :perk, :claimed], %{count: 1}, _meta}

      # Claiming again returns the same claim.
      again = claim(ctx, ctx.first, perk) |> json_response(200)
      assert again["created"] == false
      assert again["claim"]["id"] == body["claim"]["id"]

      [listed] =
        ctx.as.(ctx.owner)
        |> get("#{ctx.admin}/perks")
        |> json_response(200)
        |> Map.fetch!("perks")

      assert listed["claims_count"] == 1
      assert listed["uses_count"] == 0

      assert [_created] = analytics_events(ctx.organization.id, "perk_created")
      assert [_published] = analytics_events(ctx.organization.id, "perk_published")
      assert [_claimed] = analytics_events(ctx.organization.id, "perk_claimed")
    end

    test "staff without manage_perks are refused", ctx do
      assert ctx.as.(ctx.coach) |> get("#{ctx.admin}/perks") |> json_response(403)
    end

    test "the documents are validated for the benefit and the method", ctx do
      owner = ctx.as.(ctx.owner)

      body =
        owner
        |> send_json(:post, "#{ctx.admin}/perks", %{
          partner_name: "X",
          benefit: %{type: "free_item"},
          redemption: %{}
        })
        |> json_response(422)

      assert %{"benefit" => %{"item" => _}, "redemption" => %{"shared_code" => _}} =
               body["errors"]

      assert %{"errors" => %{"rules" => %{"limits" => %{"max_per_period" => _}}}} =
               owner
               |> send_json(
                 :post,
                 "#{ctx.admin}/perks",
                 perk_attrs(%{rules: %{limits: %{period: "week"}}})
               )
               |> json_response(422)

      assert %{"code" => "invalid_perk_packages"} =
               owner
               |> send_json(
                 :post,
                 "#{ctx.admin}/perks",
                 perk_attrs(%{rules: %{eligibility: %{package_ids: [Ecto.UUID.generate()]}}})
               )
               |> json_response(422)

      assert %{"code" => "invalid_perk_groups"} =
               owner
               |> send_json(
                 :post,
                 "#{ctx.admin}/perks",
                 perk_attrs(%{rules: %{eligibility: %{group_ids: [Ecto.UUID.generate()]}}})
               )
               |> json_response(422)

      free =
        create_perk!(ctx, %{
          benefit: %{type: "buy_x_get_y", buy_quantity: 2, get_quantity: 1, item: "bars"},
          redemption_method: "show_membership",
          redemption: %{instructions: "Δείξε την κάρτα μέλους"}
        })

      assert free["benefit_label"] == "Buy 2 get 1 bars"
      assert free["instructions"] == "Δείξε την κάρτα μέλους"
    end

    test "a business in demo mode drafts perks but can't publish them", ctx do
      Repo.query!(
        "UPDATE organizations SET activation = 'demo', provider_kind = 'gym' WHERE id = $1",
        [Ecto.UUID.dump!(ctx.organization.id)]
      )

      perk = create_perk!(ctx)

      assert %{"code" => "business_not_activated"} =
               ctx.as.(ctx.owner)
               |> send_json(:post, "#{ctx.admin}/perks/#{perk["id"]}/publish")
               |> json_response(403)
    end

    test "pause stops claims; ended perks are read-only; claimed perks keep their method", ctx do
      perk = live!(ctx)
      claim!(ctx, ctx.first, perk)
      claim!(ctx, ctx.second, perk)
      owner = ctx.as.(ctx.owner)
      path = "#{ctx.admin}/perks/#{perk["id"]}"

      assert %{"code" => "perk_locked_after_claims"} =
               owner
               |> send_json(:patch, path, %{redemption_method: "personal_qr"})
               |> json_response(409)

      assert %{"code" => "perk_cap_below_claims"} =
               owner
               |> send_json(:patch, path, %{rules: %{limits: %{max_claims: 1}}})
               |> json_response(422)

      assert %{"code" => "perk_has_claims"} =
               owner |> send_json(:delete, path) |> json_response(409)

      owner |> send_json(:post, "#{path}/pause") |> json_response(200)

      assert %{"code" => "perk_not_available"} =
               claim(ctx, ctx.person.(:member), perk) |> json_response(409)

      owner |> send_json(:post, "#{path}/expire") |> json_response(200)

      assert %{"code" => "perk_read_only"} =
               owner |> send_json(:patch, path, %{terms: "x"}) |> json_response(409)

      assert my_perks(ctx, ctx.first) == []
    end

    test "a draft nobody claimed can be deleted", ctx do
      perk = create_perk!(ctx)

      assert ctx.as.(ctx.owner)
             |> send_json(:delete, "#{ctx.admin}/perks/#{perk["id"]}")
             |> response(204)

      assert ctx.as.(ctx.owner) |> get("#{ctx.admin}/perks/#{perk["id"]}") |> json_response(404)
    end
  end

  describe "versions" do
    test "changes amend the version until the first claim, then make a new one", ctx do
      perk = create_perk!(ctx)
      owner = ctx.as.(ctx.owner)
      path = "#{ctx.admin}/perks/#{perk["id"]}"

      amended =
        owner
        |> send_json(:patch, path, %{benefit: %{percent: 15}})
        |> json_response(200)
        |> Map.fetch!("perk")

      assert %{"version" => 1, "benefit_label" => "15%"} = amended
      publish!(ctx, perk)
      first = claim!(ctx, ctx.first, perk)
      assert first["perk_version"] == 1

      revised =
        owner
        |> send_json(:patch, path, %{benefit: %{percent: 20}, terms: "Νέοι όροι"})
        |> json_response(200)
        |> Map.fetch!("perk")

      assert %{"version" => 2, "benefit_label" => "20%", "terms" => "Νέοι όροι"} = revised
      # The documents not sent carry over.
      assert revised["redemption"]["shared_code"] == "COACH-NIKOS"
      assert [_versioned] = analytics_events(ctx.organization.id, "perk_versioned")

      # The first member keeps what they agreed to; the next one gets the new terms.
      assert %{"claims" => [%{"perk_version" => 1, "benefit_label" => "15%", "terms" => terms}]} =
               ctx.as.(ctx.first) |> get("/api/me/perks/claims") |> json_response(200)

      assert terms == "Μία φορά ανά αγορά."

      second = claim!(ctx, ctx.second, perk)
      assert %{"perk_version" => 2, "benefit_label" => "20%"} = second

      # A partner-field change touches no version.
      assert %{"version" => 2} =
               owner
               |> send_json(:patch, path, %{partner_address: "Κηφισίας 1"})
               |> json_response(200)
               |> Map.fetch!("perk")

      assert %{"versions" => [%{"version" => 2}, %{"version" => 1, "benefit_label" => "15%"}]} =
               owner |> get("#{path}/versions") |> json_response(200)
    end
  end

  describe "limits" do
    test "the overall cap and the per-member cap hold", ctx do
      perk = live!(ctx, %{rules: %{limits: %{max_claims: 1}}})

      claim!(ctx, ctx.first, perk)
      assert %{"code" => "perk_sold_out"} = claim(ctx, ctx.second, perk) |> json_response(409)

      assert [%{"claimable" => false, "unavailable_reason" => "perk_sold_out"}] =
               my_perks(ctx, ctx.second)

      # Revoking the claim frees its place.
      [%{"id" => claim_id}] =
        ctx.as.(ctx.owner)
        |> get("#{ctx.admin}/perks/#{perk["id"]}/claims")
        |> json_response(200)
        |> Map.fetch!("claims")

      ctx.as.(ctx.owner)
      |> send_json(:post, "#{ctx.admin}/perk-claims/#{claim_id}/revoke")
      |> json_response(200)

      assert claim(ctx, ctx.second, perk) |> json_response(200)
    end

    test "after a use, a member claims again only up to their limit", ctx do
      perk = live!(ctx, %{rules: %{limits: %{max_per_member: 2}}})
      owner = ctx.as.(ctx.owner)

      for _round <- 1..2 do
        %{"id" => id} = claim!(ctx, ctx.first, perk)
        owner |> send_json(:post, "#{ctx.admin}/perk-claims/#{id}/use") |> json_response(200)
      end

      assert %{"code" => "perk_member_limit"} = claim(ctx, ctx.first, perk) |> json_response(409)
      assert %{"claims_count" => 2, "uses_count" => 2} = staff_perk(ctx, perk)
    end

    test "period limits hold for everyone and for each member", ctx do
      perk =
        live!(ctx, %{
          rules: %{
            limits: %{
              max_per_member: 100,
              period: "month",
              max_per_period: 2,
              max_per_member_per_period: 1
            }
          }
        })

      owner = ctx.as.(ctx.owner)
      %{"id" => id} = claim!(ctx, ctx.first, perk)
      owner |> send_json(:post, "#{ctx.admin}/perk-claims/#{id}/use") |> json_response(200)

      assert %{"code" => "perk_member_period_limit"} =
               claim(ctx, ctx.first, perk) |> json_response(409)

      assert [%{"claimable" => false, "unavailable_reason" => "perk_member_period_limit"}] =
               my_perks(ctx, ctx.first)

      claim!(ctx, ctx.second, perk)

      assert %{"code" => "perk_period_sold_out"} =
               claim(ctx, ctx.person.(:member), perk) |> json_response(409)
    end

    test "claims racing for the last place: one wins, the cap holds", ctx do
      perk = live!(ctx, %{rules: %{limits: %{max_claims: 1}}})
      users = [ctx.first, ctx.second, ctx.person.(:member), ctx.person.(:member)]

      results =
        users
        |> Enum.map(fn user ->
          Task.async(fn -> MemberPerks.claim(user_context(user), perk["id"]) end)
        end)
        |> Enum.map(&Task.await(&1, 15_000))

      assert Enum.count(results, &match?({:ok, %{created: true}}, &1)) == 1
      assert Enum.count(results, &(&1 == {:error, :perk_sold_out})) == 3
      assert %{claims_count: 1} = Perks.get_perk(ctx.owner_context, perk["id"])
    end
  end

  describe "methods" do
    test "a code pool hands each member their own code, takes CSV and alerts when low", ctx do
      TelemetryCapture.capture([[:palee, :perk, :pool_low]])

      perk =
        create_perk!(ctx, %{
          redemption_method: "code_pool",
          redemption: %{low_pool_threshold: 1}
        })

      owner = ctx.as.(ctx.owner)
      codes = "#{ctx.admin}/perks/#{perk["id"]}/codes"

      assert %{"code" => "perk_codes_required"} =
               owner
               |> send_json(:post, "#{ctx.admin}/perks/#{perk["id"]}/publish")
               |> json_response(422)

      assert %{"added" => 2, "duplicates" => 1, "total" => 2, "free" => 2, "low" => false} =
               owner
               |> send_json(:post, codes, %{codes: ["abc-1", "ABC 2", "ABC-1"]})
               |> json_response(200)

      # Top up from a CSV export; codes already in the pool count as duplicates.
      assert %{"added" => 1, "duplicates" => 1, "total" => 3, "free" => 3} =
               owner
               |> send_json(:post, codes, %{csv: "code;batch\r\nABC-1;a\r\n\"XYZ-9\";b\r\n"})
               |> json_response(200)

      assert %{"code" => "invalid_perk_codes"} =
               owner |> send_json(:post, codes, %{}) |> json_response(422)

      publish!(ctx, perk)

      %{"code" => first} = claim!(ctx, ctx.first, perk)
      %{"code" => second} = claim!(ctx, ctx.second, perk)
      refute first == second
      assert_receive {:telemetry_event, [:palee, :perk, :pool_low], %{count: 1}, _meta}
      assert [_low | _] = analytics_events(ctx.organization.id, "perk_pool_low")

      claim!(ctx, ctx.person.(:member), perk)

      assert %{"code" => "perk_codes_exhausted"} =
               claim(ctx, ctx.person.(:member), perk) |> json_response(409)

      assert %{"claims_count" => 3, "codes" => %{"free" => 0, "total" => 3, "low" => true}} =
               staff_perk(ctx, perk)
    end

    test "a partner link applies the code to the store's link", ctx do
      perk =
        live!(ctx, %{
          redemption_method: "partner_link",
          redemption: %{
            link_url: "https://shop.example/cart?coupon={code}",
            shared_code: "fit 10"
          }
        })

      assert %{
               "code" => "FIT-10",
               "url" => "https://shop.example/cart?coupon=FIT-10",
               "show_membership" => false
             } = claim!(ctx, ctx.first, perk)

      assert [%{url: "https://shop.example/cart?coupon=FIT-10", code: "FIT-10"}] =
               MemberPerks.for_member_provider(user_context(ctx.first), ctx.organization.id)
    end

    test "show your membership: no code, the claim is still recorded", ctx do
      perk = live!(ctx, %{redemption_method: "show_membership", redemption: %{}})

      assert %{"code" => nil, "show_membership" => true, "reference" => reference} =
               claim!(ctx, ctx.first, perk)

      assert reference =~ ~r/^[0-9A-Z]{8}$/
      assert %{"claims_count" => 1} = staff_perk(ctx, perk)
    end

    test "recurring windows: outside the set days and hours a perk can't be claimed", ctx do
      # A one-minute window that has just passed in the business's time.
      local = Palee.Application.Perks.local_now(ctx.owner_context)
      ends = local |> NaiveDateTime.to_time() |> Time.truncate(:second)
      starts = Time.add(ends, -60)

      if Time.compare(starts, ends) == :lt do
        perk =
          live!(ctx, %{
            rules: %{
              recurring: [
                %{
                  weekdays: [Date.day_of_week(NaiveDateTime.to_date(local))],
                  starts_at: Time.to_iso8601(starts),
                  ends_at: Time.to_iso8601(ends)
                }
              ]
            }
          })

        assert %{"code" => "perk_outside_hours"} =
                 claim(ctx, ctx.first, perk) |> json_response(409)
      end
    end
  end

  describe "the personal QR and the partner's verification link" do
    setup ctx do
      Repo.query!("UPDATE users SET display_nickname = 'Μαρία Κ.' WHERE id = $1", [
        Ecto.UUID.dump!(ctx.first.id)
      ])

      perk = live!(ctx, %{redemption_method: "personal_qr", redemption: %{}})
      claim = claim!(ctx, ctx.first, perk)
      Map.merge(ctx, %{perk: perk, qr: claim})
    end

    test "shows the perk and the member's first name only, then marks it used exactly once",
         ctx do
      TelemetryCapture.capture([[:palee, :perk, :redeemed]])
      %{"verification" => %{"token" => token, "path" => path}} = ctx.qr
      assert path == "/perks/verify/" <> token

      shown = build_conn() |> get("/api/public/perk-verifications/#{token}")
      assert get_resp_header(shown, "cache-control") == ["no-store"]
      shown = json_response(shown, 200)

      assert %{
               "status" => "valid",
               "code" => code,
               "member_first_name" => "Μαρία",
               "perk" => %{"partner_name" => "SupplementsX", "benefit_label" => "10%"}
             } = shown

      assert code == ctx.qr["code"]
      refute inspect(shown) =~ ctx.first.id
      refute inspect(shown) =~ ctx.first.nickname
      refute inspect(shown) =~ "Κ."

      conn = build_conn() |> post("/api/public/perk-verifications/#{token}/redeem")
      assert %{"status" => "used"} = json_response(conn, 200)
      assert_receive {:telemetry_event, [:palee, :perk, :redeemed], %{count: 1}, _meta}

      assert %{"code" => "perk_claim_already_used"} =
               build_conn()
               |> post("/api/public/perk-verifications/#{token}/redeem")
               |> json_response(409)

      assert %{"status" => "used"} =
               build_conn()
               |> get("/api/public/perk-verifications/#{token}")
               |> json_response(200)

      assert [%{metadata: %{"via" => "partner_link"}}] =
               analytics_events(ctx.organization.id, "perk_redeemed")

      assert %{"uses_count" => 1} = staff_perk(ctx, ctx.perk)
    end

    test "a forged, edited, expired or replaced link is refused", ctx do
      %{"verification" => %{"token" => token}} = ctx.qr

      assert %{"code" => "invalid_verification_link"} =
               build_conn()
               |> get("/api/public/perk-verifications/#{token}x")
               |> json_response(404)

      claim_id = ctx.qr["id"]
      org = ctx.organization.id
      {other_nonce, _hash} = Perks.new_secret()

      # Right signature, wrong secret.
      forged =
        SignedToken.sign(
          MemberPerks.link_salt(),
          Perks.link_payload(claim_id, org, other_nonce, DateTime.add(DateTime.utc_now(), 600))
        )

      assert build_conn() |> get("/api/public/perk-verifications/#{forged}") |> json_response(404)

      assert build_conn()
             |> post("/api/public/perk-verifications/#{forged}/redeem")
             |> json_response(404)

      # Past its own expiry.
      expired =
        SignedToken.sign(
          MemberPerks.link_salt(),
          Perks.link_payload(claim_id, org, other_nonce, DateTime.add(DateTime.utc_now(), -1))
        )

      assert %{"code" => "verification_link_expired"} =
               build_conn()
               |> get("/api/public/perk-verifications/#{expired}")
               |> json_response(410)

      # A new link for the same claim replaces the old one.
      %{"claim" => %{"verification" => %{"token" => fresh}}} =
        ctx.as.(ctx.first)
        |> send_json(:post, "/api/me/perks/claims/#{claim_id}/verification-link")
        |> json_response(200)

      assert build_conn() |> get("/api/public/perk-verifications/#{token}") |> json_response(404)
      assert build_conn() |> get("/api/public/perk-verifications/#{fresh}") |> json_response(200)

      # Another member can't ask for a link of this claim.
      assert ctx.as.(ctx.second)
             |> send_json(:post, "/api/me/perks/claims/#{claim_id}/verification-link")
             |> json_response(404)
    end

    test "a revoked claim's link stops working", ctx do
      %{"verification" => %{"token" => token}} = ctx.qr

      ctx.as.(ctx.owner)
      |> send_json(:post, "#{ctx.admin}/perk-claims/#{ctx.qr["id"]}/revoke")
      |> json_response(200)

      assert %{"status" => "revoked"} =
               build_conn()
               |> get("/api/public/perk-verifications/#{token}")
               |> json_response(200)

      assert %{"code" => "perk_claim_not_open"} =
               build_conn()
               |> post("/api/public/perk-verifications/#{token}/redeem")
               |> json_response(409)

      assert [_revoked] = analytics_events(ctx.organization.id, "perk_claim_revoked")
    end

    test "verification links are only for personal QR claims", ctx do
      shared = live!(ctx, %{partner_name: "Shared"})
      %{"id" => id, "verification" => nil} = claim!(ctx, ctx.first, shared)

      assert %{"code" => "perk_not_qr"} =
               ctx.as.(ctx.first)
               |> send_json(:post, "/api/me/perks/claims/#{id}/verification-link")
               |> json_response(422)
    end
  end

  describe "who sees a perk" do
    test "only clients see it, and package perks only their holders", ctx do
      {:ok, package} =
        Finance.create_package(ctx.owner_context, %{
          name: "Unlimited",
          package_type: "class_pack",
          base_price_cents: 5000
        })

      live!(ctx, %{rules: %{eligibility: %{package_ids: [package.id]}}})
      live!(ctx, %{partner_name: "Everyone"})

      assert ["Everyone"] = my_perks(ctx, ctx.first) |> Enum.map(& &1["partner_name"])
      # Staff only: never a client there.
      assert my_perks(ctx, ctx.coach) == []

      {:ok, membership} =
        Finance.upsert_membership(ctx.owner_context, ctx.first.id, %{
          user_type_snapshot: "member",
          status: "active",
          signup_source: "admin_created"
        })

      {:ok, _subscription} =
        Finance.assign_package(ctx.owner_context, membership.id, package.id, %{})

      assert ["Everyone", "SupplementsX"] =
               my_perks(ctx, ctx.first) |> Enum.map(& &1["partner_name"]) |> Enum.sort()
    end

    test "a demo business's perks never reach members", ctx do
      live!(ctx)

      Repo.query!(
        "UPDATE organizations SET activation = 'demo', provider_kind = 'gym' WHERE id = $1",
        [Ecto.UUID.dump!(ctx.organization.id)]
      )

      assert my_perks(ctx, ctx.first) == []
    end

    test "branch staff see and change only perks of their branches", ctx do
      {:ok, kifisia} = Facility.create_location(ctx.owner_context, %{name: "Κηφισιά"})
      {:ok, glyfada} = Facility.create_location(ctx.owner_context, %{name: "Γλυφάδα"})
      manager = ctx.person.(:admin)

      {:ok, _scope} =
        Organizations.set_membership_location_scope(ctx.owner_context, manager.id, [kifisia.id])

      glyfada_perk = create_perk!(ctx, %{all_locations: false, location_ids: [glyfada.id]})
      everywhere = create_perk!(ctx, %{partner_name: "Everywhere"})

      listed =
        ctx.as.(manager) |> get("#{ctx.admin}/perks") |> json_response(200) |> Map.fetch!("perks")

      assert Enum.map(listed, & &1["id"]) == [everywhere["id"]]

      assert ctx.as.(manager)
             |> get("#{ctx.admin}/perks/#{glyfada_perk["id"]}")
             |> json_response(404)

      # Their own perk is valid at their branch; «everywhere» needs every branch.
      mine =
        ctx.as.(manager)
        |> send_json(:post, "#{ctx.admin}/perks", perk_attrs(%{partner_name: "Local"}))
        |> json_response(201)
        |> Map.fetch!("perk")

      assert mine["location_ids"] == [kifisia.id]

      assert ctx.as.(manager)
             |> send_json(:patch, "#{ctx.admin}/perks/#{everywhere["id"]}", %{terms: "x"})
             |> json_response(403)
    end
  end

  describe "export and billing" do
    test "the claims export pages as JSON and downloads as CSV", ctx do
      TelemetryCapture.capture([[:palee, :perk, :claims_exported]])
      perk = live!(ctx)
      claim!(ctx, ctx.first, perk)
      claim!(ctx, ctx.second, perk)
      owner = ctx.as.(ctx.owner)

      page = owner |> get("#{ctx.admin}/perks/#{perk["id"]}/claims?limit=1") |> json_response(200)
      assert [%{"status" => "claimed", "perk_version" => 1}] = page["claims"]
      assert is_binary(page["next"])

      rest =
        owner
        |> get("#{ctx.admin}/perks/#{perk["id"]}/claims?limit=1&after=#{page["next"]}")
        |> json_response(200)

      assert [%{"id" => second_id}] = rest["claims"]
      refute second_id == hd(page["claims"])["id"]

      conn = owner |> get("#{ctx.admin}/perks/#{perk["id"]}/claims.csv")
      assert response(conn, 200)
      assert ["text/csv" <> _] = get_resp_header(conn, "content-type")
      [header | rows] = conn.resp_body |> String.trim() |> String.split("\r\n")
      assert header =~ "user_id,display_name,handle,perk_version,code"
      assert length(rows) == 2
      assert Enum.all?(rows, &String.contains?(&1, ",1,COACH-NIKOS,claimed,"))
      assert_receive {:telemetry_event, [:palee, :perk, :claims_exported], %{count: 1}, _meta}

      # A cell a spreadsheet would read as a formula is defused; commas are quoted.
      csv = PerkPresenter.csv([%{id: "1", display_name: "=cmd()", handle: "a,b", code: "C"}])
      assert csv =~ ~s|1,,'=cmd(),"a,b",,C,|
    end

    test "the billing slot lists the member's usable claims in the BillingPerk shape", ctx do
      until = ctx.owner_context |> Palee.Application.Perks.today() |> Date.add(30)
      perk = live!(ctx, %{rules: %{valid_until: Date.to_iso8601(until)}})
      assert MemberPerks.for_member_provider(user_context(ctx.first), ctx.organization.id) == []

      claim!(ctx, ctx.first, perk)

      assert [
               %{
                 id: id,
                 store: "SupplementsX",
                 discount: "10%",
                 code: "COACH-NIKOS",
                 terms: "Μία φορά ανά αγορά.",
                 valid_until: ^until,
                 url: "https://supplementsx.example"
               }
             ] = MemberPerks.for_member_provider(user_context(ctx.first), ctx.organization.id)

      assert id == perk["id"]

      # Not a client: nothing.
      assert MemberPerks.for_member_provider(user_context(ctx.coach), ctx.organization.id) == []
    end
  end
end
