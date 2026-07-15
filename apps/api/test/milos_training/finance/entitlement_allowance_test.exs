defmodule MilosTraining.Finance.EntitlementAllowanceTest do
  use MilosTraining.DataCase

  alias MilosTraining.Finance
  alias MilosTraining.TestFixtures

  @plan %{
    "entitlement_version" => 1,
    "channels" => ["in_person"],
    "capabilities" => ["book_classes"],
    "allowances" => %{
      "class_visits" => %{"limit" => 2, "period" => "calendar_month"}
    }
  }

  test "serially reserves, releases, and extends one member's allowance with audit history" do
    user = TestFixtures.user_fixture(%{role: :member})
    admin = TestFixtures.admin_fixture()

    {:ok, package} =
      Finance.create_package(%{
        code: "twice_monthly",
        name: "Twice monthly",
        family: "limited-visits",
        billing_period: "monthly",
        params: @plan
      })

    {:ok, membership} =
      Finance.upsert_membership(user.id, %{
        user_type_snapshot: "member",
        status: "active",
        signup_source: "admin_created"
      })

    {:ok, _subscription} =
      Finance.assign_package(membership.id, package.id, %{starts_on: Date.utc_today()})

    request = %{
      channel: :in_person,
      capability: :book_classes,
      allowance: :class_visits,
      source_context: "scheduling",
      quantity: 1,
      occurred_on: Date.utc_today()
    }

    assert {:ok, first} =
             Finance.reserve_entitlement(
               user.id,
               Map.put(request, :idempotency_key, "booking:one")
             )

    assert {:ok, _second} =
             Finance.reserve_entitlement(
               user.id,
               Map.put(request, :idempotency_key, "booking:two")
             )

    assert {:ok, repeated_first} =
             Finance.reserve_entitlement(
               user.id,
               Map.put(request, :idempotency_key, "booking:one")
             )

    assert repeated_first.id == first.id

    assert {:error, :finance_allowance_exhausted, %{limit: 2, committed: 2}} =
             Finance.reserve_entitlement(
               user.id,
               Map.put(request, :idempotency_key, "booking:three")
             )

    assert {:ok, grant} =
             Finance.grant_allowance(user.id, admin.id, %{
               allowance: :class_visits,
               quantity: 1,
               period: :calendar_month,
               occurred_on: Date.utc_today(),
               reason: "Competition preparation",
               idempotency_key: "grant:competition"
             })

    assert grant.event_type == "adjustment"
    assert grant.quantity_delta == -1

    assert {:ok, _third} =
             Finance.reserve_entitlement(
               user.id,
               Map.put(request, :idempotency_key, "booking:three")
             )

    assert {:ok, release} =
             Finance.release_entitlement(first.id, %{
               reason: "Booking withdrawn",
               idempotency_key: "release:booking:one"
             })

    assert release.quantity_delta == -1
    assert release.parent_entry_id == first.id

    effective = Finance.get_effective_entitlement(user.id)
    assert effective.allowances.class_visits.limit == 2
    assert effective.allowances.class_visits.committed == 2
    assert effective.allowances.class_visits.extensions == 1
    assert effective.allowances.class_visits.remaining == 1
    assert length(effective.usage_entries) == 5
  end
end
