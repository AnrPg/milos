defmodule Palee.Perks.PerkRulesTest do
  use ExUnit.Case, async: true

  alias Palee.Perks.{PerkVersion, Rules}
  alias Palee.Perks.Domain.{PerkRules, VerificationToken}

  @today ~D[2026-12-15]
  @now ~U[2026-12-15 10:00:00.000000Z]
  # Tuesday 15 December 2026, 10:00 local.
  @local ~N[2026-12-15 10:00:00]

  defp version(attrs \\ %{}) do
    params =
      Map.merge(
        %{
          benefit: %{type: "percent", percent: 10},
          rules: %{},
          redemption: %{shared_code: "coach nikos"},
          terms: "Μία φορά ανά αγορά."
        },
        attrs
      )

    changeset = PerkVersion.changeset(%PerkVersion{version: 1}, params, "shared_code")
    assert changeset.valid?, inspect(changeset.errors)
    Ecto.Changeset.apply_changes(changeset)
  end

  defp perk(attrs \\ %{}, version_attrs \\ %{}) do
    Map.merge(
      %{
        status: "published",
        valid_from: nil,
        valid_until: nil,
        published_at: nil,
        claims_count: 0,
        current_version: 1,
        all_locations: true,
        location_ids: [],
        redemption_method: "shared_code",
        version: version(version_attrs)
      },
      attrs
    )
  end

  defp rules(attrs) do
    changeset = Rules.changeset(attrs)
    assert changeset.valid?, inspect(changeset.errors)
    Ecto.Changeset.apply_changes(changeset)
  end

  defp facts(attrs \\ %{}),
    do: Map.merge(%{today: @today, local_now: @local, member_claims: 0, period: nil}, attrs)

  describe "lifecycle" do
    test "a published perk past its window reads as expired" do
      assert PerkRules.effective_status(perk(%{valid_until: ~D[2026-12-14]}), @today) == "expired"
      assert PerkRules.effective_status(perk(%{valid_until: @today}), @today) == "published"
      assert PerkRules.effective_status(perk(%{status: "draft"}), @today) == "draft"
    end

    test "draft and paused publish; published pauses; both end" do
      assert {:ok, %{status: "published", published_at: @now}} =
               PerkRules.transition(perk(%{status: "draft"}), :publish, @now, @today)

      first = ~U[2026-12-01 08:00:00.000000Z]

      assert {:ok, %{status: "published", published_at: ^first, paused_at: nil}} =
               PerkRules.transition(
                 perk(%{status: "paused", published_at: first}),
                 :publish,
                 @now,
                 @today
               )

      assert {:ok, %{status: "paused"}} = PerkRules.transition(perk(), :pause, @now, @today)
      assert {:ok, %{status: "expired"}} = PerkRules.transition(perk(), :expire, @now, @today)

      assert {:ok, %{status: "expired"}} =
               PerkRules.transition(perk(%{status: "paused"}), :expire, @now, @today)
    end

    test "steps the status doesn't allow, and publishing past the window, are refused" do
      assert {:error, :perk_transition_invalid} =
               PerkRules.transition(perk(%{status: "draft"}), :pause, @now, @today)

      assert {:error, :perk_transition_invalid} =
               PerkRules.transition(perk(%{status: "expired"}), :publish, @now, @today)

      assert {:error, :perk_transition_invalid} =
               PerkRules.transition(perk(), :publish, @now, @today)

      assert {:error, :perk_ended} =
               PerkRules.transition(
                 perk(%{status: "draft", valid_until: ~D[2026-12-01]}),
                 :publish,
                 @now,
                 @today
               )
    end
  end

  describe "updates and versions" do
    test "ended perks are read-only; claimed ones keep their method and cap" do
      assert {:error, :perk_read_only} =
               PerkRules.check_update(perk(%{status: "expired"}), %{}, nil, @today)

      claimed = perk(%{claims_count: 3})
      assert :ok = PerkRules.check_update(claimed, %{partner_name: "New"}, nil, @today)

      assert {:error, :perk_locked_after_claims} =
               PerkRules.check_update(claimed, %{redemption_method: "code_pool"}, nil, @today)

      assert {:error, :perk_cap_below_claims} =
               PerkRules.check_update(claimed, %{}, rules(%{limits: %{max_claims: 2}}), @today)

      assert :ok =
               PerkRules.check_update(claimed, %{}, rules(%{limits: %{max_claims: 3}}), @today)

      # Before any claim the method may change.
      assert :ok = PerkRules.check_update(perk(), %{redemption_method: "code_pool"}, nil, @today)
    end

    test "a version is amended until the first claim, then a new one is made" do
      assert PerkRules.version_mode(perk()) == :amend
      assert PerkRules.version_mode(perk(%{claims_count: 1})) == :new

      base = PerkVersion.next_base(version())
      assert base.version == nil
      assert base.benefit.percent == 10
    end
  end

  describe "eligibility" do
    test "branches, packages, groups and tenure narrow who may claim" do
      package = Ecto.UUID.generate()
      group = Ecto.UUID.generate()
      branch = Ecto.UUID.generate()
      everyone = %{package_ids: [], group_ids: [], home_location_id: nil, today: @today}

      assert PerkRules.for_member?(perk(), everyone)

      for_package = perk(%{}, %{rules: %{eligibility: %{package_ids: [package]}}})
      refute PerkRules.for_member?(for_package, everyone)
      assert PerkRules.for_member?(for_package, %{everyone | package_ids: [package]})

      for_group = perk(%{}, %{rules: %{eligibility: %{group_ids: [group]}}})
      refute PerkRules.for_member?(for_group, everyone)
      assert PerkRules.for_member?(for_group, %{everyone | group_ids: [group]})

      tenure = perk(%{}, %{rules: %{eligibility: %{min_tenure_days: 30}}})
      refute PerkRules.for_member?(tenure, everyone)
      refute PerkRules.for_member?(tenure, Map.put(everyone, :joined_on, ~D[2026-12-01]))
      assert PerkRules.for_member?(tenure, Map.put(everyone, :joined_on, ~D[2026-11-15]))

      at_branch = perk(%{all_locations: false, location_ids: [branch]})
      assert PerkRules.for_member?(at_branch, %{everyone | home_location_id: branch})

      refute PerkRules.for_member?(at_branch, %{everyone | home_location_id: Ecto.UUID.generate()})

      # Members without a home branch roam (ADR-186).
      assert PerkRules.for_member?(at_branch, everyone)
    end
  end

  describe "claims" do
    test "only a live perk under its caps can be claimed" do
      assert :ok = PerkRules.claim_check(perk(), facts())

      assert {:error, :perk_not_available} =
               PerkRules.claim_check(perk(%{status: "paused"}), facts())

      assert {:error, :perk_not_available} =
               PerkRules.claim_check(perk(%{valid_from: ~D[2026-12-16]}), facts())

      capped = perk(%{claims_count: 5}, %{rules: %{limits: %{max_claims: 5}}})
      assert {:error, :perk_sold_out} = PerkRules.claim_check(capped, facts())

      assert {:error, :perk_member_limit} =
               PerkRules.claim_check(perk(), facts(%{member_claims: 1}))

      twice = perk(%{}, %{rules: %{limits: %{max_per_member: 2}}})
      assert :ok = PerkRules.claim_check(twice, facts(%{member_claims: 1}))
    end

    test "period limits count everyone and each member since the period started" do
      weekly =
        perk(%{}, %{
          rules: %{
            limits: %{
              max_per_member: 100,
              period: "week",
              max_per_period: 50,
              max_per_member_per_period: 1
            }
          }
        })

      assert :ok = PerkRules.claim_check(weekly, facts(%{period: %{all: 49, member: 0}}))

      assert {:error, :perk_period_sold_out} =
               PerkRules.claim_check(weekly, facts(%{period: %{all: 50, member: 0}}))

      assert {:error, :perk_member_period_limit} =
               PerkRules.claim_check(weekly, facts(%{period: %{all: 3, member: 1}}))
    end

    test "periods start at local midnight, Monday or the 1st" do
      limits = fn period ->
        rules(%{limits: %{period: period, max_per_member_per_period: 1}})
      end

      assert PerkRules.period_start(limits.("day"), @local) == ~N[2026-12-15 00:00:00]
      assert PerkRules.period_start(limits.("week"), @local) == ~N[2026-12-14 00:00:00]
      assert PerkRules.period_start(limits.("month"), @local) == ~N[2026-12-01 00:00:00]
      assert PerkRules.period_start(rules(%{}), @local) == nil
    end

    test "recurring windows limit claims and uses to their days and hours" do
      mornings = %{
        rules: %{recurring: [%{weekdays: [1, 2, 3, 4, 5], starts_at: "06:00", ends_at: "10:00"}]}
      }

      perk = perk(%{}, mornings)
      assert :ok = PerkRules.claim_check(perk, facts(%{local_now: ~N[2026-12-15 09:59:00]}))

      assert {:error, :perk_outside_hours} =
               PerkRules.claim_check(perk, facts(%{local_now: ~N[2026-12-15 10:00:00]}))

      # Saturday.
      assert {:error, :perk_outside_hours} =
               PerkRules.claim_check(perk, facts(%{local_now: ~N[2026-12-19 08:00:00]}))

      claim = %{status: "claimed"}

      assert {:error, :perk_outside_hours} =
               PerkRules.usable(perk, perk.version.rules, claim, @today, ~N[2026-12-19 08:00:00])

      assert :ok =
               PerkRules.usable(perk, perk.version.rules, claim, @today, ~N[2026-12-18 08:00:00])
    end

    test "a claim is usable while unused and the perk is published or paused in its window" do
      claimed = %{status: "claimed"}

      usable? = fn perk, claim ->
        PerkRules.usable?(perk, perk.version.rules, claim, @today, @local)
      end

      assert usable?.(perk(), claimed)
      assert usable?.(perk(%{status: "paused"}), claimed)
      refute usable?.(perk(%{status: "expired"}), claimed)
      refute usable?.(perk(%{valid_until: ~D[2026-12-14]}), claimed)
      refute usable?.(perk(), %{status: "used"})

      assert {:error, :perk_claim_already_used} =
               PerkRules.usable(perk(), perk().version.rules, %{status: "used"}, @today, @local)

      assert {:error, :perk_claim_not_open} =
               PerkRules.usable(
                 perk(),
                 perk().version.rules,
                 %{status: "revoked"},
                 @today,
                 @local
               )
    end

    test "remaining claims under the cap" do
      assert PerkRules.remaining(perk()) == nil

      assert PerkRules.remaining(perk(%{claims_count: 3}, %{rules: %{limits: %{max_claims: 5}}})) ==
               2
    end
  end

  describe "the benefit in one line" do
    test "each type" do
      label = fn benefit -> PerkRules.benefit_label(version(%{benefit: benefit}).benefit) end

      assert label.(%{type: "percent", percent: 10}) == "10%"
      assert label.(%{type: "fixed_amount", amount_cents: 505, currency: "eur"}) == "5.05 EUR"
      assert label.(%{type: "free_item", item: "shaker"}) == "Free shaker"
      assert label.(%{type: "buy_x_get_y", buy_quantity: 2, get_quantity: 1}) == "Buy 2 get 1"

      assert label.(%{type: "buy_x_get_y", buy_quantity: 2, get_quantity: 1, item: "bars"}) ==
               "Buy 2 get 1 bars"

      assert label.(%{type: "free_text", text: "Δωρεάν αξιολόγηση"}) == "Δωρεάν αξιολόγηση"
    end
  end

  describe "verification token" do
    test "the secret is stored as a hash and compared in constant time" do
      {nonce, hash} = VerificationToken.new_secret()
      assert byte_size(nonce) >= 43
      refute hash == nonce
      assert VerificationToken.matches?(hash, nonce)
      refute VerificationToken.matches?(hash, nonce <> "x")
      refute VerificationToken.matches?(nil, nonce)
    end

    test "a link lives at most the maximum, never past the perk's last day" do
      assert {:ok, expires} = VerificationToken.expires_at(@now, nil)

      assert DateTime.diff(expires, DateTime.truncate(@now, :second)) ==
               VerificationToken.max_seconds()

      assert {:ok, ~U[2026-12-16 00:00:00Z]} =
               VerificationToken.expires_at(~U[2026-12-15 23:50:00Z], @today)

      assert {:error, :perk_not_available} = VerificationToken.expires_at(@now, ~D[2026-12-14])
    end

    test "payloads parse until they expire and reject any other shape" do
      {nonce, _hash} = VerificationToken.new_secret()
      claim = Ecto.UUID.generate()
      org = Ecto.UUID.generate()
      payload = VerificationToken.payload(claim, org, nonce, DateTime.add(@now, 60))

      assert {:ok, %{claim_id: ^claim, organization_id: ^org, nonce: ^nonce}} =
               VerificationToken.parse(payload, @now)

      assert {:error, :verification_link_expired} =
               VerificationToken.parse(payload, DateTime.add(@now, 61))

      assert {:error, :invalid_verification_link} =
               VerificationToken.parse(Map.put(payload, "v", 2), @now)

      assert {:error, :invalid_verification_link} = VerificationToken.parse(%{"c" => claim}, @now)
    end

    test "display codes are 8 characters of Crockford base32" do
      assert VerificationToken.display_code() =~ ~r/^[0-9A-HJKMNP-TV-Z]{8}$/
    end
  end
end
