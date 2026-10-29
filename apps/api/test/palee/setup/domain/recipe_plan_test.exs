defmodule Palee.Setup.Domain.RecipePlanTest do
  @moduledoc "ADR-255: the dry-run plan of a recipe over a snapshot of the business."

  use ExUnit.Case, async: true

  alias Palee.Setup.Domain.{Recipe, RecipePlan}

  @recipe %Recipe{
    key: "test_box",
    version: 3,
    names: %{"en" => "Test box", "el" => "Δοκιμαστικό box"},
    summaries: %{"en" => "x", "el" => "x"},
    provider_kind: "gym",
    settings: %{
      "scheduling.default_capacity" => 16,
      "scheduling.default_auto_approve" => true,
      "finance.package_modules" => ["open_gym", "group_classes"],
      "trials.conversion_package_id" => "setup_unlimited"
    },
    class_types: [
      %{slug: "wod", names: %{"en" => "WOD", "el" => "WOD"}},
      %{slug: "kids", names: %{"en" => "Kids", "el" => "Παιδιά"}, audiences: ["kids"]}
    ],
    packages: [
      %{
        code: "setup_unlimited",
        names: %{"en" => "Unlimited monthly", "el" => "Απεριόριστο μηνιαίο"},
        package_type: "membership",
        billing_period: "monthly",
        base_price_cents: 8_000,
        fields: %{}
      }
    ],
    role_grants: %{"front_desk" => ["manage_billing"]},
    documents: [
      %{
        key: "health_certificate",
        names: %{"en" => "Health certificate", "el" => "Βεβαίωση υγείας"}
      }
    ]
  }

  @fresh %{
    locale: "el",
    provider_kind: "gym",
    settings: %{
      "scheduling.default_capacity" => 12,
      "scheduling.default_auto_approve" => false,
      "finance.package_modules" => ["group_classes", "online_coaching"],
      "trials.conversion_package_id" => nil
    },
    class_type_names: [],
    package_codes: [],
    role_grants: %{},
    documents: :unsupported
  }

  defp keys(changes), do: Enum.map(changes, & &1.key)

  test "on a fresh business every step is a change, in dependency order" do
    plan = RecipePlan.build(@recipe, @fresh)

    assert plan.recipe == "test_box"
    assert plan.version == 3

    assert keys(plan.changes) == [
             "package.setup_unlimited",
             "class_type.wod",
             "class_type.kids",
             "finance.package_modules",
             "scheduling.default_auto_approve",
             "scheduling.default_capacity",
             "trials.conversion_package_id",
             "access.role_grants.front_desk"
           ]

    assert plan.unchanged == ["provider.kind"]
    refute RecipePlan.empty?(plan)
  end

  test "creations carry the attributes in the business's language" do
    plan = RecipePlan.build(@recipe, @fresh)
    package = Enum.find(plan.changes, &(&1.area == "package"))

    assert package.action == "create"
    assert package.name == "Απεριόριστο μηνιαίο"

    assert package.attrs == %{
             code: "setup_unlimited",
             name: "Απεριόριστο μηνιαίο",
             package_type: "membership",
             billing_period: "monthly",
             base_price_cents: 8_000,
             fields: %{}
           }

    kids = Enum.find(plan.changes, &(&1.key == "class_type.kids"))
    assert kids.attrs == %{name: "Παιδιά", kind: "class", audiences: ["kids"]}

    english = RecipePlan.build(@recipe, %{@fresh | locale: "en"})
    assert Enum.find(english.changes, &(&1.area == "package")).name == "Unlimited monthly"
  end

  test "settings show from and to, and whether they are advanced" do
    plan = RecipePlan.build(@recipe, @fresh)
    capacity = Enum.find(plan.changes, &(&1.key == "scheduling.default_capacity"))

    assert %{area: "setting", action: "set", from: 12, to: 16, advanced: false} = capacity

    modules = Enum.find(plan.changes, &(&1.key == "finance.package_modules"))
    assert modules.advanced
  end

  test "documents are manual while the business has no templates" do
    plan = RecipePlan.build(@recipe, @fresh)

    assert [%{area: "document", action: "manual", name: "Βεβαίωση υγείας"}] = plan.manual

    with_templates = RecipePlan.build(@recipe, %{@fresh | documents: []})
    assert [] = with_templates.manual
    assert Enum.any?(with_templates.changes, &(&1.key == "document.health_certificate"))

    done = RecipePlan.build(@recipe, %{@fresh | documents: ["health_certificate"]})
    assert "document.health_certificate" in done.unchanged
  end

  test "once everything is in place the plan is empty (idempotent)" do
    applied = %{
      @fresh
      | settings: %{
          "scheduling.default_capacity" => 16,
          "scheduling.default_auto_approve" => true,
          # Lists compare as sets.
          "finance.package_modules" => ["group_classes", "open_gym"],
          "trials.conversion_package_id" => "6f0c2c8e-0000-4000-8000-000000000000"
        },
        class_type_names: ["wod", "παιδιά"],
        package_codes: ["setup_unlimited"],
        role_grants: %{"front_desk" => ["manage_billing", "manage_shop"]}
    }

    plan = RecipePlan.build(@recipe, applied)

    assert plan.changes == []
    assert RecipePlan.empty?(plan)
    assert "class_type.kids" in plan.unchanged
  end

  test "the trial conversion never replaces the owner's choice" do
    chosen = put_in(@fresh, [:settings, "trials.conversion_package_id"], "some-id")
    plan = RecipePlan.build(@recipe, chosen)

    refute "trials.conversion_package_id" in keys(plan.changes)
    assert "trials.conversion_package_id" in plan.unchanged
  end

  test "role grants are only added to" do
    plan =
      RecipePlan.build(@recipe, %{@fresh | role_grants: %{"front_desk" => ["manage_shop"]}})

    grant = Enum.find(plan.changes, &(&1.area == "role_grant"))
    assert grant.from == ["manage_shop"]
    assert grant.to == ["manage_billing", "manage_shop"]
    assert grant.action == "add"
  end

  test "a different provider kind is a change" do
    plan = RecipePlan.build(%{@recipe | provider_kind: "coach"}, @fresh)
    assert %{area: "provider", from: "gym", to: "coach"} = hd(plan.changes)
  end

  test "class type names compare trimmed and case-insensitive" do
    plan =
      RecipePlan.build(@recipe, %{@fresh | class_type_names: [RecipePlan.normalize_name(" Wod ")]})

    assert "class_type.wod" in plan.unchanged
  end

  describe "the owner's own values (product decision 2026-10-29)" do
    test "a setting no longer at its catalog default is marked owner_changed" do
      # Capacity 12 and auto approve false are the catalog defaults; 20 is the owner's.
      fresh = RecipePlan.build(@recipe, @fresh)
      refute Enum.find(fresh.changes, &(&1.key == "scheduling.default_capacity")).owner_changed

      chosen = put_in(@fresh, [:settings, "scheduling.default_capacity"], 20)
      plan = RecipePlan.build(@recipe, chosen)
      capacity = Enum.find(plan.changes, &(&1.key == "scheduling.default_capacity"))
      assert %{from: 20, to: 16, owner_changed: true} = capacity
      assert plan.kept == []
    end

    test "a value the snapshot does not know is not the owner's" do
      unknown = %{@fresh | settings: Map.delete(@fresh.settings, "scheduling.default_capacity")}
      plan = RecipePlan.build(@recipe, unknown)
      refute Enum.find(plan.changes, &(&1.key == "scheduling.default_capacity")).owner_changed
    end

    test "defaults_only keeps the owner's values and applies the rest" do
      chosen = put_in(@fresh, [:settings, "scheduling.default_capacity"], 20)
      plan = chosen |> then(&RecipePlan.build(@recipe, &1)) |> RecipePlan.for_mode(:defaults_only)

      refute "scheduling.default_capacity" in keys(plan.changes)
      assert "scheduling.default_auto_approve" in keys(plan.changes)
      assert plan.kept == ["scheduling.default_capacity"]

      all = chosen |> then(&RecipePlan.build(@recipe, &1)) |> RecipePlan.for_mode(:all)
      assert "scheduling.default_capacity" in keys(all.changes)
    end

    test "modes by name" do
      assert {:ok, :all} = RecipePlan.mode(nil)
      assert {:ok, :all} = RecipePlan.mode("all")
      assert {:ok, :defaults_only} = RecipePlan.mode("defaults_only")
      assert {:error, :invalid_recipe_mode} = RecipePlan.mode("some")
      assert {:error, :invalid_recipe_mode} = RecipePlan.mode(3)
    end
  end
end
