defmodule MilosTraining.Application.BackfillFinanceEntitlementsTest do
  use MilosTraining.DataCase, async: false

  alias MilosTraining.Application.BackfillFinanceEntitlements
  alias MilosTraining.Finance

  import MilosTraining.TestFixtures

  test "dry-run reports missing profiles without mutating and apply is idempotent" do
    member = user_fixture()
    athlete = user_fixture(%{role: :athlete})
    package = package_fixture("legacy_all_access")

    params = %{package_by_role: %{member: package.id, athlete: package.id}}

    assert {:ok, dry_run} = BackfillFinanceEntitlements.call(Map.put(params, :dry_run, true))
    assert dry_run.ready == false
    assert dry_run.counts.create_and_assign == 2
    assert Finance.get_member_profile(member.id) == nil

    assert {:ok, applied} = BackfillFinanceEntitlements.call(Map.put(params, :dry_run, false))
    assert applied.counts.applied == 2
    assert Finance.get_member_profile(member.id).active_package_subscription
    assert Finance.get_member_profile(athlete.id).active_package_subscription

    assert {:ok, repeated} = BackfillFinanceEntitlements.call(Map.put(params, :dry_run, false))
    assert repeated.ready
    assert repeated.counts.unchanged == 2
    assert repeated.counts.applied == 0
  end

  test "rejects a legacy target package without a versioned entitlement plan" do
    _member = user_fixture()

    {:ok, package} =
      Finance.create_package(%{
        code: "legacy_untyped",
        name: "Legacy untyped",
        family: "unlimited",
        billing_period: "monthly"
      })

    assert {:error, {:invalid_backfill_package, "member", :unsupported_entitlement_version}} =
             BackfillFinanceEntitlements.call(%{
               dry_run: true,
               package_by_role: %{member: package.id}
             })
  end

  defp package_fixture(code) do
    {:ok, package} =
      Finance.create_package(%{
        code: code,
        name: "Legacy all access",
        family: "hybrid",
        billing_period: "monthly",
        params: %{
          "entitlement_version" => 1,
          "channels" => ["in_person", "workout_library", "personal_programming"],
          "capabilities" => [
            "book_classes",
            "execute_class_workouts",
            "execute_library_workouts",
            "execute_assigned_workouts",
            "receive_coaching_touchpoints"
          ],
          "allowances" => %{
            "class_visits" => %{"limit" => "unlimited", "period" => "calendar_month"},
            "coaching_touchpoints" => %{
              "limit" => "unlimited",
              "period" => "calendar_month"
            }
          }
        }
      })

    package
  end
end
