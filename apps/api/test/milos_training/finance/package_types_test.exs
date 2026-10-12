defmodule MilosTraining.Finance.PackageTypesTest do
  use MilosTraining.DataCase

  alias MilosTraining.{Finance, Organizations}
  alias MilosTraining.TestFixtures

  @class_type_a "11111111-1111-4111-8111-111111111111"
  @class_type_b "22222222-2222-4222-8222-222222222222"

  setup do
    owner = TestFixtures.admin_fixture()

    {:ok, organization} =
      Organizations.create_organization(%{
        name: "Package Types Test #{System.unique_integer([:positive])}"
      })

    {:ok, _membership} =
      Organizations.add_membership(%{
        organization_id: organization.id,
        user_id: owner.id,
        role: :owner,
        status: :active,
        joined_at: DateTime.utc_now()
      })

    Repo.query!("SELECT set_config($1, $2, false)", ["app.organization_id", organization.id])
    Repo.query!("SELECT set_config($1, $2, false)", ["app.user_id", owner.id])

    {:ok, _settings} =
      Finance.update_finance_settings(%{
        entitlement_enforcement_mode: "enforce_managed",
        entitlement_timezone: "Europe/Athens",
        payment_reminder_interval_days: 7
      })

    %{organization: organization}
  end

  defp member do
    user = TestFixtures.user_fixture(%{role: :member})

    {:ok, membership} =
      Finance.upsert_membership(user.id, %{
        user_type_snapshot: "member",
        status: "active",
        signup_source: "admin_created"
      })

    {user, membership}
  end

  defp booking_request(key, class_type_id \\ nil) do
    %{
      channel: :in_person,
      capability: :book_classes,
      allowance: :class_visits,
      class_type_id: class_type_id,
      source_context: "scheduling",
      source_id: Ecto.UUID.generate(),
      quantity: 1,
      occurred_on: Date.utc_today(),
      idempotency_key: key
    }
  end

  describe "package writes" do
    test "creates v2 packages with a transliterated, unique, immutable code" do
      assert {:ok, first} =
               Finance.create_package(%{
                 name: "Απεριόριστο Μηνιαίο",
                 package_type: "membership",
                 billing_period: "monthly",
                 base_price_cents: 6000
               })

      assert first.code == "aperioristo_miniaio"
      assert first.package_type == "membership"
      assert first.family == "membership"
      assert first.params["entitlement_version"] == 2
      assert first.fields["group_classes.included"]
      assert first.changed_fields == []

      assert {:ok, second} =
               Finance.create_package(%{name: "Απεριόριστο μηνιαίο!", package_type: "membership"})

      assert second.code == "aperioristo_miniaio_2"

      assert {:ok, renamed} =
               Finance.update_package(first.id, %{name: "Unlimited monthly", code: "other"})

      assert renamed.code == "aperioristo_miniaio"
      assert renamed.name == "Unlimited monthly"
    end

    test "rejects locked, unavailable and unimplemented changes" do
      assert {:error, {:package_type_invariant_violated, "group_classes.visits.limit"}} =
               Finance.create_package(%{
                 name: "Drop in",
                 package_type: "drop_in",
                 fields: %{
                   "group_classes.visits" => %{"limit" => 3, "period" => "subscription_period"}
                 }
               })

      assert {:error, {:entitlement_not_available, "content.workout_library"}} =
               Finance.create_package(%{
                 name: "Annual",
                 package_type: "membership",
                 billing_period: "annual",
                 fields: %{"content.workout_library" => true}
               })

      assert {:error, :package_type_not_available} =
               Finance.create_package(%{name: "Corporate", package_type: "corporate"})
    end

    test "records changed fields and blocks type changes once the package is sold" do
      {:ok, package} =
        Finance.create_package(%{
          name: "Eight a month",
          package_type: "membership",
          fields: %{"group_classes.visits" => %{"limit" => 8, "period" => "calendar_month"}}
        })

      assert package.changed_fields == ["group_classes.visits"]

      {_user, membership} = member()
      {:ok, _} = Finance.assign_package(membership.id, package.id, %{starts_on: Date.utc_today()})

      assert {:error, :package_type_change_requires_copy} =
               Finance.update_package(package.id, %{package_type: "class_pack"})

      assert {:ok, updated} =
               Finance.update_package(package.id, %{
                 fields: %{
                   "group_classes.visits" => %{"limit" => 12, "period" => "calendar_month"}
                 }
               })

      assert updated.fields["group_classes.visits"]["limit"] == 12
    end
  end

  describe "assignment" do
    test "one-off packages derive their end date and cannot be renewed" do
      {:ok, pack} = Finance.create_package(%{name: "Ten visits", package_type: "class_pack"})
      {_user, membership} = member()

      assert {:ok, historical} =
               Finance.assign_package(membership.id, pack.id, %{starts_on: ~D[2026-01-31]})

      assert historical.ends_on == ~D[2026-04-29]
      assert historical.package_type == "class_pack"

      {:ok, subscription} = Finance.assign_package(membership.id, pack.id, %{})

      assert {:error, :package_not_renewable} =
               Finance.generate_renewal_invoice(membership.id, %{
                 "membership_package_subscription_id" => subscription.id
               })
    end

    test "trials are once per person and for new members only" do
      {:ok, trial} = Finance.create_package(%{name: "Trial week", package_type: "trial"})
      {:ok, monthly} = Finance.create_package(%{name: "Monthly", package_type: "membership"})

      {_user, newcomer} = member()
      assert {:ok, _} = Finance.assign_package(newcomer.id, trial.id, %{})

      assert {:error, :package_already_used} =
               Finance.assign_package(newcomer.id, trial.id, %{})

      {_user, existing} = member()
      {:ok, _} = Finance.assign_package(existing.id, monthly.id, %{})

      assert {:error, :package_new_members_only} =
               Finance.assign_package(existing.id, trial.id, %{})
    end
  end

  describe "enforcement" do
    test "class packs stack and are consumed by earliest expiry after the membership" do
      {:ok, two_visits} =
        Finance.create_package(%{
          name: "Two visits",
          package_type: "class_pack",
          fields: %{
            "group_classes.visits" => %{"limit" => 2, "period" => "subscription_period"},
            "terms.validity" => %{"amount" => 1, "unit" => "month"}
          }
        })

      {:ok, one_visit} =
        Finance.create_package(%{
          name: "One visit",
          package_type: "class_pack",
          fields: %{"group_classes.visits" => %{"limit" => 1, "period" => "subscription_period"}}
        })

      {user, membership} = member()
      {:ok, long} = Finance.assign_package(membership.id, one_visit.id, %{})
      {:ok, short} = Finance.assign_package(membership.id, two_visits.id, %{})

      assert {:ok, first} = Finance.reserve_entitlement(user.id, booking_request("stack:1"))
      assert {:ok, second} = Finance.reserve_entitlement(user.id, booking_request("stack:2"))
      assert {:ok, third} = Finance.reserve_entitlement(user.id, booking_request("stack:3"))

      assert first.membership_package_subscription_id == short.id
      assert second.membership_package_subscription_id == short.id
      assert third.membership_package_subscription_id == long.id

      assert {:error, :finance_allowance_exhausted, _} =
               Finance.reserve_entitlement(user.id, booking_request("stack:4"))
    end

    test "class-type scope and per-type limits are enforced" do
      {:ok, package} =
        Finance.create_package(%{
          name: "Reformer limited",
          package_type: "membership",
          fields: %{
            "group_classes.class_types" => [@class_type_a, @class_type_b],
            "group_classes.class_type_limits" => [
              %{"id" => @class_type_b, "limit" => 1, "period" => "calendar_month"}
            ]
          }
        })

      {user, membership} = member()
      {:ok, _} = Finance.assign_package(membership.id, package.id, %{})

      assert {:ok, limited} =
               Finance.reserve_entitlement(user.id, booking_request("scope:b1", @class_type_b))

      assert limited.allowance_key == "class_visits:" <> @class_type_b

      assert {:error, :finance_allowance_exhausted, _} =
               Finance.reserve_entitlement(user.id, booking_request("scope:b2", @class_type_b))

      # TD-050: personal grants can extend a per-class-type limit.
      admin = TestFixtures.admin_fixture()

      assert {:ok, grant} =
               Finance.grant_allowance(user.id, admin.id, %{
                 allowance: "class_visits:" <> @class_type_b,
                 quantity: 1,
                 occurred_on: Date.utc_today(),
                 reason: "Make-up class",
                 idempotency_key: "grant:reformer"
               })

      assert grant.allowance_key == "class_visits:" <> @class_type_b

      assert {:ok, _extra} =
               Finance.reserve_entitlement(user.id, booking_request("scope:b3", @class_type_b))

      assert {:ok, general} =
               Finance.reserve_entitlement(user.id, booking_request("scope:a1", @class_type_a))

      assert general.allowance_key == "class_visits"

      assert {:error, :finance_class_type_not_included, %{class_type_id: _}} =
               Finance.reserve_entitlement(
                 user.id,
                 booking_request("scope:c1", Ecto.UUID.generate())
               )

      # Attendance finalizes per-class-type reservations through the generic allowance.
      assert {:ok, finalized} =
               Finance.finalize_entitlement_source(
                 user.id,
                 "scheduling",
                 limited.source_id,
                 :class_visits,
                 %{idempotency_key: "scope:finalize"}
               )

      assert finalized.event_type == "finalize"
      assert finalized.allowance_key == "class_visits:" <> @class_type_b
    end

    test "coaching packages authorize programming delivery" do
      {:ok, package} =
        Finance.create_package(%{
          name: "Online coaching",
          package_type: "membership",
          fields: %{"group_classes.included" => false, "online_coaching.included" => true}
        })

      {user, membership} = member()
      {:ok, _} = Finance.assign_package(membership.id, package.id, %{})

      assert {:ok, reservation} =
               Finance.reserve_entitlement(user.id, %{
                 channel: :personal_programming,
                 capability: :receive_coaching_touchpoints,
                 allowance: :coaching_touchpoints,
                 quantity: 1,
                 occurred_on: Date.utc_today(),
                 source_context: "workouts",
                 idempotency_key: "coaching:1"
               })

      assert reservation.allowance_key == "coaching_touchpoints"

      assert {:error, :finance_channel_not_included, %{channel: :in_person}} =
               Finance.reserve_entitlement(user.id, booking_request("coaching:booking"))
    end
  end
end
