defmodule MilosTraining.Finance.Domain.PackageContractTest do
  use ExUnit.Case, async: true

  alias MilosTraining.Finance.Domain.{
    EntitlementPlan,
    EntitlementPolicy,
    PackageCatalog,
    PackageCode,
    PackageContract,
    PackagePresets,
    PackageType,
    SubscriptionSelection
  }

  @class_type_a "11111111-1111-4111-8111-111111111111"
  @class_type_b "22222222-2222-4222-8222-222222222222"

  describe "presets" do
    test "every type preset covers exactly the catalog" do
      assert :ok = PackagePresets.assert_complete!()

      for type <- PackageType.keys() do
        assert {:ok, preset} = PackagePresets.preset(type)
        assert Enum.sort(Map.keys(preset)) == Enum.sort(PackageCatalog.keys())
      end
    end

    test "every preset value is valid for its field" do
      for type <- PackageType.keys(), {key, value} <- elem(PackagePresets.preset(type), 1) do
        {:ok, spec} = PackageCatalog.fetch(key)
        assert {:ok, ^value} = PackageCatalog.cast(spec, value), "#{type} #{key}"
      end
    end

    test "every available type preset normalizes without changes" do
      for %{key: type} = definition <- PackageType.types(), PackageType.available?(definition) do
        assert {:ok, %{fields: fields}} = PackageContract.normalize(%{"package_type" => type})
        {:ok, preset} = PackagePresets.preset(type)
        assert fields == preset, type
      end
    end

    test "every preset satisfies its own locks" do
      for type <- PackageType.keys(), {path, locked, _reason} <- PackagePresets.locks(type) do
        {:ok, preset} = PackagePresets.preset(type)
        field = PackagePresets.lock_field(path)
        assert PackagePresets.locked_value(preset[field], path) == locked, "#{type} #{path}"
      end
    end

    test "billing period adjusts dependent preset values" do
      assert {:ok, %{"perks.freeze_days_per_year" => 30}} =
               PackagePresets.preset("membership", "annual")

      assert {:ok, %{"perks.freeze_days_per_year" => 0}} =
               PackagePresets.preset("membership", "monthly")
    end
  end

  describe "normalize/2" do
    test "class packs keep an editable visit count but a locked counting period" do
      assert {:ok, %{billing_period: "one_off", fields: fields}} =
               PackageContract.normalize(%{
                 "package_type" => "class_pack",
                 "fields" => %{
                   "group_classes.visits" => %{"limit" => 20, "period" => "subscription_period"}
                 }
               })

      assert fields["group_classes.visits"] == %{"limit" => 20, "period" => "subscription_period"}
      assert fields["terms.auto_renew"] == false

      assert {:error, {:package_type_invariant_violated, "group_classes.visits.period"}} =
               PackageContract.normalize(%{
                 "package_type" => "class_pack",
                 "fields" => %{
                   "group_classes.visits" => %{"limit" => 20, "period" => "calendar_month"}
                 }
               })

      assert {:error, {:package_rule_violated, :limited_quota_required, "group_classes.visits"}} =
               PackageContract.normalize(%{
                 "package_type" => "class_pack",
                 "fields" => %{
                   "group_classes.visits" => %{
                     "limit" => "unlimited",
                     "period" => "subscription_period"
                   }
                 }
               })
    end

    test "drop-ins lock a single visit and one-off billing" do
      assert {:error, {:package_type_invariant_violated, "group_classes.visits.limit"}} =
               PackageContract.normalize(%{
                 "package_type" => "drop_in",
                 "fields" => %{
                   "group_classes.visits" => %{"limit" => 5, "period" => "subscription_period"}
                 }
               })

      assert {:error, {:package_type_invariant_violated, "billing_period"}} =
               PackageContract.normalize(%{
                 "package_type" => "drop_in",
                 "billing_period" => "monthly"
               })

      assert {:error, {:package_type_invariant_violated, "terms.auto_renew"}} =
               PackageContract.normalize(%{
                 "package_type" => "drop_in",
                 "fields" => %{"terms.auto_renew" => true}
               })
    end

    test "trials lock once-per-person but keep new-members-only editable" do
      assert {:ok, %{fields: fields}} =
               PackageContract.normalize(%{
                 "package_type" => "trial",
                 "fields" => %{"terms.new_members_only" => false}
               })

      assert fields["terms.once_per_person"]
      refute fields["terms.new_members_only"]

      assert {:error, {:package_type_invariant_violated, "terms.once_per_person"}} =
               PackageContract.normalize(%{
                 "package_type" => "trial",
                 "fields" => %{"terms.once_per_person" => false}
               })
    end

    test "memberships accept every implemented customization" do
      assert {:ok, %{billing_period: "quarterly", fields: fields}} =
               PackageContract.normalize(%{
                 "package_type" => "membership",
                 "billing_period" => "quarterly",
                 "fields" => %{
                   "terms.auto_renew" => false,
                   "group_classes.visits" => %{"limit" => 8, "period" => "calendar_month"},
                   "group_classes.class_types" => [@class_type_a, @class_type_b],
                   "group_classes.class_type_limits" => [
                     %{"id" => @class_type_b, "limit" => 4, "period" => "calendar_month"}
                   ],
                   "online_coaching.included" => true,
                   "online_coaching.touchpoints" => %{"limit" => 4, "period" => "calendar_month"},
                   "facility.amenities" => ["towel", "sauna"],
                   "facility.amenities_note" => "  Free coffee  "
                 }
               })

      assert fields["facility.amenities"] == ["sauna", "towel"]
      assert fields["facility.amenities_note"] == "Free coffee"
      assert fields["perks.freeze_days_per_year"] == 7
    end

    test "unimplemented fields cannot deviate from the preset" do
      assert {:error, {:entitlement_not_available, "content.workout_library"}} =
               PackageContract.normalize(%{
                 "package_type" => "membership",
                 "fields" => %{"content.workout_library" => true}
               })

      assert {:ok, _} =
               PackageContract.normalize(%{
                 "package_type" => "membership",
                 "fields" => %{"content.workout_library" => false}
               })
    end

    test "unimplemented types cannot be created" do
      for type <- ["add_on", "shared", "corporate"] do
        assert {:error, :package_type_not_available} =
                 PackageContract.normalize(%{"package_type" => type})
      end
    end

    test "unknown fields, invalid values and broken rules are rejected" do
      assert {:error, {:unknown_package_field, "teleport.included"}} =
               PackageContract.normalize(%{
                 "package_type" => "membership",
                 "fields" => %{"teleport.included" => true}
               })

      assert {:error, {:invalid_package_field, "group_classes.visits", :invalid_quota_limit}} =
               PackageContract.normalize(%{
                 "package_type" => "membership",
                 "fields" => %{
                   "group_classes.visits" => %{"limit" => -1, "period" => "calendar_month"}
                 }
               })

      assert {:error, {:package_rule_violated, :at_least_one_service, _}} =
               PackageContract.normalize(%{
                 "package_type" => "membership",
                 "fields" => %{"group_classes.included" => false}
               })

      assert {:error, {:package_rule_violated, :coaching_channel_required, _}} =
               PackageContract.normalize(%{
                 "package_type" => "membership",
                 "fields" => %{
                   "online_coaching.included" => true,
                   "online_coaching.assigned_programming" => false,
                   "online_coaching.messaging" => false
                 }
               })

      assert {:error, {:package_rule_violated, :class_type_limit_outside_scope, _}} =
               PackageContract.normalize(%{
                 "package_type" => "membership",
                 "fields" => %{
                   "group_classes.class_types" => [@class_type_a],
                   "group_classes.class_type_limits" => [
                     %{"id" => @class_type_b, "limit" => 2, "period" => "calendar_week"}
                   ]
                 }
               })
    end

    test "updates merge onto the stored contract and type changes restart from the preset" do
      {:ok, existing} =
        PackageContract.normalize(%{
          "package_type" => "membership",
          "fields" => %{"group_classes.visits" => %{"limit" => 8, "period" => "calendar_week"}}
        })

      assert {:ok, %{fields: fields}} =
               PackageContract.normalize(%{"fields" => %{"terms.auto_renew" => false}},
                 existing: existing
               )

      assert fields["group_classes.visits"]["limit"] == 8
      refute fields["terms.auto_renew"]

      assert {:ok, %{package_type: "class_pack", fields: fields}} =
               PackageContract.normalize(%{"package_type" => "class_pack"}, existing: existing)

      assert fields["group_classes.visits"] == %{"limit" => 10, "period" => "subscription_period"}
    end

    test "changed fields are reported against the preset" do
      {:ok, %{fields: fields}} =
        PackageContract.normalize(%{
          "package_type" => "membership",
          "fields" => %{"terms.auto_renew" => false}
        })

      assert PackageContract.changed_fields("membership", "monthly", fields) == [
               "terms.auto_renew"
             ]
    end
  end

  describe "plan compilation" do
    test "v1 plans are presented as an equivalent membership contract" do
      fields =
        PackageContract.fields_from_params(%{
          "entitlement_version" => 1,
          "channels" => ["in_person", "coach_messaging"],
          "capabilities" => ["book_classes"],
          "allowances" => %{"class_visits" => %{"limit" => 3, "period" => "calendar_week"}}
        })

      assert fields["group_classes.included"]
      assert fields["group_classes.visits"] == %{"limit" => 3, "period" => "calendar_week"}
      assert fields["online_coaching.included"]
      assert fields["online_coaching.messaging"]
      refute fields["online_coaching.assigned_programming"]
    end

    test "v2 contracts compile into channels, capabilities and allowances" do
      {:ok, contract} =
        PackageContract.normalize(%{
          "package_type" => "membership",
          "fields" => %{
            "online_coaching.included" => true,
            "online_coaching.messaging" => false,
            "group_classes.class_types" => [@class_type_a, @class_type_b],
            "group_classes.class_type_limits" => [
              %{"id" => @class_type_b, "limit" => 4, "period" => "calendar_month"}
            ]
          }
        })

      assert {:ok, plan} = EntitlementPlan.parse(PackageContract.to_params(contract))
      assert plan.version == 2
      assert plan.package_type == "membership"
      assert MapSet.equal?(plan.channels, MapSet.new([:in_person, :personal_programming]))

      assert MapSet.equal?(
               plan.capabilities,
               MapSet.new([
                 :book_classes,
                 :execute_class_workouts,
                 :execute_assigned_workouts,
                 :receive_coaching_touchpoints
               ])
             )

      assert plan.allowances.class_visits.limit == :unlimited
      assert plan.allowances.coaching_touchpoints.period == :calendar_month
      assert plan.allowances["class_visits:" <> @class_type_b].limit == 4

      assert EntitlementPlan.resolve_allowance(plan, :class_visits, @class_type_b) ==
               "class_visits:" <> @class_type_b

      assert EntitlementPlan.resolve_allowance(plan, :class_visits, @class_type_a) ==
               :class_visits
    end

    test "class types outside the scope are denied under enforcement" do
      {:ok, contract} =
        PackageContract.normalize(%{
          "package_type" => "membership",
          "fields" => %{"group_classes.class_types" => [@class_type_a]}
        })

      entitlement = %{status: "active", plan: PackageContract.to_params(contract)}
      request = %{channel: :in_person, capability: :book_classes, class_type_id: @class_type_b}

      assert {:error, :finance_class_type_not_included} =
               EntitlementPolicy.authorize(entitlement, request, mode: :enforce_all)

      assert {:ok, %{observed?: true, reason: :finance_class_type_not_included}} =
               EntitlementPolicy.authorize(entitlement, request, mode: :observe)

      assert {:ok, _} =
               EntitlementPolicy.authorize(
                 entitlement,
                 %{request | class_type_id: @class_type_a},
                 mode: :enforce_all
               )
    end

    test "coaching packages include the touchpoint capability required by programming delivery" do
      {:ok, contract} =
        PackageContract.normalize(%{
          "package_type" => "membership",
          "fields" => %{"online_coaching.included" => true}
        })

      entitlement = %{status: "active", plan: PackageContract.to_params(contract)}

      assert {:ok, _} =
               EntitlementPolicy.authorize(
                 entitlement,
                 %{
                   channel: :personal_programming,
                   capability: :receive_coaching_touchpoints,
                   allowance: :coaching_touchpoints,
                   committed: 0
                 },
                 mode: :enforce_all
               )
    end
  end

  describe "catalog document" do
    test "the web test fixture matches the served catalog" do
      fixture =
        Path.expand(
          "../web/src/components/admin/finance/packages/__fixtures__/package-catalog.json",
          File.cwd!()
        )

      served =
        ["group_classes", "online_coaching"]
        |> MilosTraining.Finance.Domain.PackageCatalogDocument.build()
        |> Jason.encode!()
        |> Jason.decode!()

      # Regenerate with PackageCatalogDocument.build/1 when presets or locks change.
      assert Jason.decode!(File.read!(fixture)) == served
    end
  end

  describe "package codes" do
    test "transliterates Greek names and normalizes punctuation" do
      assert PackageCode.normalize("Απεριόριστο Μηνιαίο") == "aperioristo_miniaio"
      assert PackageCode.normalize("10 Επισκέψεις / Ευεξία") == "10_episkepseis_evexia"
      assert PackageCode.normalize("Unlimited Monthly!") == "unlimited_monthly"
      assert PackageCode.normalize("   ") == nil
    end

    test "adds a numeric suffix on collision" do
      assert PackageCode.unique("trial", []) == "trial"
      assert PackageCode.unique("trial", ["trial", "trial_2"]) == "trial_3"
    end
  end

  describe "subscription selection" do
    defp subscription(type, starts_on, ends_on, package_id \\ "p") do
      {:ok, contract} = PackageContract.normalize(%{"package_type" => type})

      %{
        id: "#{type}-#{ends_on}",
        membership_package_id: package_id,
        starts_on: starts_on,
        ends_on: ends_on,
        params_snapshot: PackageContract.to_params(contract)
      }
    end

    test "tries recurring subscriptions first and one-off packages by earliest expiry" do
      late_pack = subscription("class_pack", ~D[2026-10-01], ~D[2026-12-31])
      early_pack = subscription("class_pack", ~D[2026-10-05], ~D[2026-11-04])
      membership = subscription("membership", ~D[2026-10-01], nil)

      assert Enum.map(SubscriptionSelection.order([late_pack, early_pack, membership]), & &1.id) ==
               [membership.id, early_pack.id, late_pack.id]
    end

    test "derives end dates from package validity" do
      {:ok, contract} = PackageContract.normalize(%{"package_type" => "class_pack"})
      params = PackageContract.to_params(contract)
      assert SubscriptionSelection.ends_on(~D[2026-01-31], params) == ~D[2026-04-29]

      {:ok, contract} = PackageContract.normalize(%{"package_type" => "trial"})

      assert SubscriptionSelection.ends_on(~D[2026-10-12], PackageContract.to_params(contract)) ==
               ~D[2026-10-18]

      {:ok, contract} = PackageContract.normalize(%{"package_type" => "membership"})

      assert SubscriptionSelection.ends_on(~D[2026-10-12], PackageContract.to_params(contract)) ==
               nil
    end

    test "enforces trial eligibility against subscription history" do
      {:ok, contract} = PackageContract.normalize(%{"package_type" => "trial"})
      params = PackageContract.to_params(contract)

      assert :ok = SubscriptionSelection.eligible?("trial-id", params, [])

      assert {:error, :package_already_used} =
               SubscriptionSelection.eligible?("trial-id", params, [
                 subscription("trial", ~D[2026-01-01], ~D[2026-01-07], "trial-id")
               ])

      assert {:error, :package_new_members_only} =
               SubscriptionSelection.eligible?("trial-id", params, [
                 subscription("membership", ~D[2026-01-01], nil, "other")
               ])
    end

    test "only renewing recurring packages can be renewed" do
      {:ok, membership} = PackageContract.normalize(%{"package_type" => "membership"})
      assert :ok = SubscriptionSelection.renewable?(PackageContract.to_params(membership))

      {:ok, fixed} =
        PackageContract.normalize(%{
          "package_type" => "membership",
          "fields" => %{"terms.auto_renew" => false}
        })

      assert {:error, :package_not_renewable} =
               SubscriptionSelection.renewable?(PackageContract.to_params(fixed))

      {:ok, pack} = PackageContract.normalize(%{"package_type" => "class_pack"})

      assert {:error, :package_not_renewable} =
               SubscriptionSelection.renewable?(PackageContract.to_params(pack))

      assert :ok =
               SubscriptionSelection.renewable?(%{
                 "entitlement_version" => 1,
                 "channels" => [],
                 "capabilities" => [],
                 "allowances" => %{}
               })
    end
  end
end
