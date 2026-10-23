defmodule Palee.Perks.PerkDocumentsTest do
  @moduledoc "ADR-191: the validated documents of a perk version and the method strategies."
  use ExUnit.Case, async: true

  alias Palee.Perks.{Benefit, PerkVersion, Redemption, Rules}
  alias Palee.Perks.Domain.{CodeImport, RedemptionMethod}
  alias Palee.Perks.Domain.Methods.CodePool

  defp errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, _opts} -> message end)
  end

  describe "benefit" do
    test "each type requires its own fields" do
      assert Benefit.changeset(%{type: "percent", percent: 15}).valid?
      assert %{percent: _} = errors(Benefit.changeset(%{type: "percent"}))
      assert %{percent: _} = errors(Benefit.changeset(%{type: "percent", percent: 150}))

      fixed = Benefit.changeset(%{type: "fixed_amount", amount_cents: 500, currency: "eur"})
      assert fixed.valid?
      assert Ecto.Changeset.get_field(fixed, :currency) == "EUR"
      assert %{amount_cents: _} = errors(Benefit.changeset(%{type: "fixed_amount"}))

      assert %{currency: _} =
               errors(
                 Benefit.changeset(%{type: "fixed_amount", amount_cents: 1, currency: "EURO"})
               )

      assert Benefit.changeset(%{type: "free_item", item: "shaker"}).valid?
      assert %{item: _} = errors(Benefit.changeset(%{type: "free_item"}))

      assert Benefit.changeset(%{type: "buy_x_get_y", buy_quantity: 2, get_quantity: 1}).valid?

      assert %{get_quantity: _} =
               errors(Benefit.changeset(%{type: "buy_x_get_y", buy_quantity: 2}))

      assert Benefit.changeset(%{type: "free_text", text: "Δωρεάν αξιολόγηση"}).valid?
      assert %{text: _} = errors(Benefit.changeset(%{type: "free_text"}))

      assert %{type: _} = errors(Benefit.changeset(%{type: "cashback"}))
    end

    test "min spend and cap are optional and positive; the schema version is stamped" do
      changeset =
        Benefit.changeset(%{
          type: "percent",
          percent: 20,
          min_spend_cents: 3000,
          max_discount_cents: 1000
        })

      assert changeset.valid?
      assert Ecto.Changeset.apply_changes(changeset).schema_version == Benefit.schema_version()

      assert %{min_spend_cents: _} =
               errors(Benefit.changeset(%{type: "percent", percent: 20, min_spend_cents: 0}))
    end
  end

  describe "rules" do
    test "defaults: always valid, both channels, one claim per member" do
      rules = %{} |> Rules.changeset() |> Ecto.Changeset.apply_changes()
      assert rules.channel == "both"
      assert rules.recurring == []
      assert rules.limits.max_per_member == 1
      assert rules.eligibility.package_ids == []
      assert rules.schema_version == Rules.schema_version()
    end

    test "window, channel and recurring windows are validated" do
      assert %{valid_until: _} =
               errors(Rules.changeset(%{valid_from: ~D[2026-12-10], valid_until: ~D[2026-12-01]}))

      assert %{channel: _} = errors(Rules.changeset(%{channel: "phone"}))

      assert Rules.changeset(%{
               channel: "online",
               recurring: [%{weekdays: [1, 2], starts_at: "06:00:00", ends_at: "10:00:00"}]
             }).valid?

      assert %{recurring: [%{ends_at: _}]} =
               errors(
                 Rules.changeset(%{
                   recurring: [%{weekdays: [1], starts_at: "10:00:00", ends_at: "06:00:00"}]
                 })
               )

      assert %{recurring: [%{weekdays: _}]} =
               errors(
                 Rules.changeset(%{
                   recurring: [%{weekdays: [0, 8], starts_at: "06:00:00", ends_at: "10:00:00"}]
                 })
               )
    end

    test "a period needs a period cap and a period cap needs a period" do
      assert Rules.changeset(%{limits: %{period: "month", max_per_period: 100}}).valid?

      assert %{limits: %{max_per_period: _}} =
               errors(Rules.changeset(%{limits: %{period: "month"}}))

      assert %{limits: %{period: _}} =
               errors(Rules.changeset(%{limits: %{max_per_member_per_period: 1}}))

      assert %{limits: %{period: _}} =
               errors(Rules.changeset(%{limits: %{period: "year", max_per_period: 1}}))

      assert %{limits: %{max_claims: _}} = errors(Rules.changeset(%{limits: %{max_claims: 0}}))
    end

    test "eligibility takes ids and a positive tenure" do
      assert Rules.changeset(%{
               eligibility: %{package_ids: [Ecto.UUID.generate()], min_tenure_days: 90}
             }).valid?

      assert %{eligibility: %{min_tenure_days: _}} =
               errors(Rules.changeset(%{eligibility: %{min_tenure_days: 0}}))

      assert %{eligibility: %{package_ids: _}} =
               errors(Rules.changeset(%{eligibility: %{package_ids: ["nope"]}}))
    end
  end

  describe "redemption methods" do
    test "the registry lists the five methods, shared code first and by default" do
      assert RedemptionMethod.keys() ==
               ~w(shared_code code_pool partner_link show_membership personal_qr)

      assert RedemptionMethod.default() == "shared_code"
      assert {:error, :invalid_redemption_method} = RedemptionMethod.fetch("qr")
      assert RedemptionMethod.verifiable?("personal_qr")
      refute RedemptionMethod.verifiable?("shared_code")
    end

    test "each method asks for its own settings" do
      cs = fn attrs, method -> Redemption.changeset(%Redemption{}, attrs, method) end

      shared = cs.(%{shared_code: "coach nikos"}, "shared_code")
      assert shared.valid?
      assert Ecto.Changeset.get_field(shared, :shared_code) == "COACH-NIKOS"
      assert %{shared_code: _} = errors(cs.(%{}, "shared_code"))

      assert cs.(%{}, "code_pool").valid?
      assert %{low_pool_threshold: _} = errors(cs.(%{low_pool_threshold: -1}, "code_pool"))

      assert cs.(%{}, "personal_qr").valid?
      assert cs.(%{instructions: "Δείξε το στο ταμείο"}, "show_membership").valid?

      assert cs.(%{link_url: "https://shop.example/offer"}, "partner_link").valid?
      assert %{link_url: _} = errors(cs.(%{link_url: "http://shop.example"}, "partner_link"))
      assert %{link_url: _} = errors(cs.(%{}, "partner_link"))

      assert %{shared_code: _} =
               errors(cs.(%{link_url: "https://shop.example/?c={code}"}, "partner_link"))

      assert cs.(%{link_url: "https://shop.example/?c={code}", shared_code: "X1"}, "partner_link").valid?

      assert %{redemption_method: _} = errors(cs.(%{}, "carrier_pigeon"))
    end

    test "what each method reveals to the member" do
      assert %{code: "ABC", url: nil, show_membership: false} =
               RedemptionMethod.reveal("shared_code", %{}, "ABC")

      assert %{code: "P-1"} = RedemptionMethod.reveal("code_pool", %{}, "P-1")

      assert %{code: nil, show_membership: true} =
               RedemptionMethod.reveal("show_membership", %{}, "REF12345")

      assert %{code: "A B", url: "https://shop.example/?c=A+B"} =
               RedemptionMethod.reveal(
                 "partner_link",
                 %{link_url: "https://shop.example/?c={code}", shared_code: "A B"},
                 "A B"
               )

      assert %{code: nil, url: "https://shop.example/offer"} =
               RedemptionMethod.reveal(
                 "partner_link",
                 %{link_url: "https://shop.example/offer", shared_code: nil},
                 "REF12345"
               )
    end

    test "a code pool goes live only with free codes and alerts when low" do
      assert {:error, :perk_codes_required} =
               RedemptionMethod.ready("code_pool", %{free_codes: 0})

      assert :ok = RedemptionMethod.ready("code_pool", %{free_codes: 1})
      assert :ok = RedemptionMethod.ready("shared_code", %{free_codes: 0})

      assert CodePool.low?(%{}, 10)
      refute CodePool.low?(%{}, 11)
      assert CodePool.low?(%{low_pool_threshold: 50}, 50)
      refute CodePool.low?(%{low_pool_threshold: 0}, 1)
    end
  end

  describe "version" do
    test "a version needs a benefit and casts its documents for its method" do
      assert %{benefit: _} =
               errors(PerkVersion.changeset(%PerkVersion{version: 1}, %{}, "show_membership"))

      changeset =
        PerkVersion.changeset(
          %PerkVersion{version: 1},
          %{
            benefit: %{type: "free_item", item: "shaker"},
            rules: %{},
            redemption: %{},
            terms: "Ένα ανά μέλος"
          },
          "show_membership"
        )

      assert changeset.valid?
      version = Ecto.Changeset.apply_changes(changeset)
      assert version.rules.limits.max_per_member == 1
      assert version.redemption.schema_version == Redemption.schema_version()

      assert %{redemption: %{shared_code: _}} =
               errors(
                 PerkVersion.changeset(
                   %PerkVersion{version: 1},
                   %{benefit: %{type: "percent", percent: 5}, rules: %{}, redemption: %{}},
                   "shared_code"
                 )
               )
    end
  end

  describe "CSV import" do
    test "reads the first column, skips a header and blank lines, undoes quotes" do
      csv = "﻿code,expires\r\nABC-1,2026-12-31\n\"Q,1\",x\n\nDEF;2\n\tGHI\tz\n"
      assert {:ok, ["ABC-1", "Q,1", "DEF", "GHI"]} = CodeImport.parse(csv)

      assert {:ok, ["X"]} = CodeImport.parse("Κωδικός\nX")
      assert {:error, :invalid_perk_codes} = CodeImport.parse("code\n\n")
      assert {:error, :invalid_perk_codes} = CodeImport.parse(nil)

      assert {:error, :invalid_perk_codes} =
               CodeImport.parse(String.duplicate("A", CodeImport.max_bytes() + 1))
    end
  end
end
