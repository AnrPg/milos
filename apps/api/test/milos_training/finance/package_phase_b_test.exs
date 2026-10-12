defmodule MilosTraining.Finance.PackagePhaseBTest do
  use MilosTraining.DataCase

  alias MilosTraining.{Finance, Organizations}
  alias MilosTraining.TestFixtures

  setup do
    owner = TestFixtures.admin_fixture()

    {:ok, organization} =
      Organizations.create_organization(%{name: "Phase B #{System.unique_integer([:positive])}"})

    {:ok, _} =
      Organizations.add_membership(%{
        organization_id: organization.id,
        user_id: owner.id,
        role: :owner,
        status: :active,
        joined_at: DateTime.utc_now()
      })

    Repo.query!("SELECT set_config($1, $2, false)", ["app.organization_id", organization.id])
    Repo.query!("SELECT set_config($1, $2, false)", ["app.user_id", owner.id])

    {:ok, _} =
      Finance.update_finance_settings(%{
        entitlement_enforcement_mode: "enforce_managed",
        entitlement_timezone: "Europe/Athens",
        payment_reminder_interval_days: 7
      })

    %{owner: owner}
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

  defp visit(key, extra \\ %{}) do
    Map.merge(
      %{
        channel: :in_person,
        capability: :book_classes,
        allowance: :class_visits,
        source_context: "scheduling",
        source_id: Ecto.UUID.generate(),
        quantity: 1,
        occurred_on: Date.utc_today(),
        idempotency_key: key
      },
      extra
    )
  end

  test "freezes block reservations, extend dated subscriptions and give back unused days", %{
    owner: owner
  } do
    {:ok, pack} =
      Finance.create_package(%{
        name: "Pack",
        package_type: "class_pack",
        fields: %{"perks.freeze_days_per_year" => 10}
      })

    {user, membership} = member()
    {:ok, subscription} = Finance.assign_package(membership.id, pack.id, %{})
    today = Date.utc_today()

    assert {:ok, freeze} =
             Finance.create_freeze(user.id, owner.id, %{
               starts_on: today,
               ends_on: Date.add(today, 4),
               reason: "Injury"
             })

    assert freeze.extension_days == 5

    assert {:error, :finance_membership_frozen} =
             Finance.reserve_entitlement(user.id, visit("frozen:1"))

    assert {:error, :freeze_allowance_exceeded} =
             Finance.create_freeze(user.id, owner.id, %{
               starts_on: Date.add(today, 10),
               ends_on: Date.add(today, 20),
               reason: "Holiday"
             })

    [stored] = Finance.list_freezes(user.id)
    assert stored.id == freeze.id

    entitlement = Finance.get_effective_entitlement(user.id)

    assert Date.compare(entitlement.subscription.ends_on, Date.add(subscription.ends_on, 5)) ==
             :eq

    assert {:ok, cancelled} = Finance.cancel_freeze(user.id, freeze.id, %{reason: "Recovered"})
    assert cancelled.extension_days == 0
    assert {:ok, _} = Finance.reserve_entitlement(user.id, visit("unfrozen:1"))

    entitlement = Finance.get_effective_entitlement(user.id)
    assert entitlement.subscription.ends_on == subscription.ends_on
  end

  test "first-use packages activate on the first reservation" do
    {:ok, pack} =
      Finance.create_package(%{
        name: "First use",
        package_type: "class_pack",
        fields: %{"terms.validity_starts" => "first_use"}
      })

    {user, membership} = member()
    {:ok, subscription} = Finance.assign_package(membership.id, pack.id, %{})
    assert subscription.ends_on == nil

    assert {:ok, _} = Finance.reserve_entitlement(user.id, visit("first-use:1"))
    entitlement = Finance.get_effective_entitlement(user.id)
    assert entitlement.subscription.activated_on == Date.utc_today()
    assert entitlement.subscription.ends_on
  end

  test "minimum commitment blocks cancellation without a reason" do
    {:ok, package} =
      Finance.create_package(%{
        name: "Committed",
        package_type: "membership",
        fields: %{"terms.minimum_commitment_months" => 12}
      })

    {user, membership} = member()
    {:ok, subscription} = Finance.assign_package(membership.id, package.id, %{})
    assert subscription.commitment_ends_on

    assert {:error, {:package_commitment_active, %{commitment_ends_on: _}}} =
             Finance.upsert_membership(user.id, %{status: "cancelled"})

    assert {:ok, %{status: "cancelled"}} =
             Finance.upsert_membership(user.id, %{
               status: "cancelled",
               commitment_override_reason: "Relocation"
             })
  end

  test "joining fees and member discounts are applied to invoices" do
    {:ok, package} =
      Finance.create_package(%{
        name: "With fee",
        package_type: "membership",
        base_price_cents: 6000,
        fields: %{
          "terms.joining_fee_cents" => 2500,
          "perks.member_discount_percent" => 10,
          "perks.member_discount_scope" => ["products"]
        }
      })

    {_user, membership} = member()
    {:ok, subscription} = Finance.assign_package(membership.id, package.id, %{})

    assert {:ok, invoice} =
             Finance.create_invoice(membership.id, %{
               "membership_package_subscription_id" => subscription.id
             })

    descriptions = Enum.map(invoice.lines, & &1.description)
    assert "Joining fee" in descriptions
    assert invoice.total_cents == 8500

    assert {:ok, second} =
             Finance.create_invoice(membership.id, %{
               "membership_package_subscription_id" => subscription.id
             })

    refute "Joining fee" in Enum.map(second.lines, & &1.description)

    assert {:ok, shop} =
             Finance.create_invoice(membership.id, %{
               "lines" => [
                 %{
                   "line_type" => "manual_charge",
                   "charge_category" => "product",
                   "description" => "Shaker",
                   "quantity" => 1,
                   "unit_amount_cents" => 2000
                 }
               ]
             })

    [line] = shop.lines
    assert line.discount_cents == 200
    assert shop.total_cents == 1800
  end

  test "unused visits roll over from the previous month" do
    {:ok, package} =
      Finance.create_package(%{
        name: "Two a month",
        package_type: "membership",
        fields: %{
          "group_classes.visits" => %{"limit" => 2, "period" => "calendar_month"},
          "group_classes.rollover_max" => 1
        }
      })

    {user, membership} = member()
    previous_month = Date.utc_today() |> Date.beginning_of_month() |> Date.add(-1)

    {:ok, _} =
      Finance.assign_package(membership.id, package.id, %{
        starts_on: Date.beginning_of_month(previous_month)
      })

    assert {:ok, _} = Finance.reserve_entitlement(user.id, visit("roll:1"))
    assert {:ok, _} = Finance.reserve_entitlement(user.id, visit("roll:2"))
    assert {:ok, _} = Finance.reserve_entitlement(user.id, visit("roll:3"))

    assert {:error, :finance_allowance_exhausted, _} =
             Finance.reserve_entitlement(user.id, visit("roll:4"))
  end

  test "booking terms and expiry reminders come from the effective package" do
    {:ok, pack} =
      Finance.create_package(%{
        name: "Reminder pack",
        package_type: "class_pack",
        fields: %{
          "booking.cancellation_cutoff_hours" => 6,
          "booking.waitlist_priority" => "high",
          "terms.expiry_reminder_days" => 3,
          "terms.validity" => %{"amount" => 3, "unit" => "day"}
        }
      })

    {user, membership} = member()
    {:ok, _} = Finance.assign_package(membership.id, pack.id, %{})

    terms = Finance.booking_terms(user.id, Date.utc_today())
    assert terms.cancellation_cutoff_hours == 6
    assert terms.waitlist_priority == "high"

    assert [] = Finance.FinanceStore.subscriptions_due_for_expiry_reminder(Date.utc_today())

    assert [%{user_id: user_id, days: 3}] =
             Finance.FinanceStore.subscriptions_due_for_expiry_reminder(
               Date.add(Date.utc_today(), -1)
             )

    assert user_id == user.id
  end

  test "time windows deny bookings outside the allowed hours" do
    {:ok, package} =
      Finance.create_package(%{
        name: "Mornings",
        package_type: "membership",
        fields: %{
          "group_classes.time_windows" => [
            %{"days" => [1, 2, 3, 4, 5, 6, 7], "from" => "06:00", "to" => "10:00"}
          ]
        }
      })

    {user, membership} = member()
    {:ok, _} = Finance.assign_package(membership.id, package.id, %{})
    date = Date.utc_today()

    # 05:00 UTC is 07:00 or 08:00 in Athens; 15:00 UTC is in the afternoon.
    morning = DateTime.new!(date, ~T[05:00:00], "Etc/UTC")
    afternoon = DateTime.new!(date, ~T[15:00:00], "Etc/UTC")

    assert {:ok, _} =
             Finance.reserve_entitlement(user.id, visit("window:1", %{starts_at: morning}))

    assert {:error, :finance_time_window_not_included} =
             Finance.reserve_entitlement(user.id, visit("window:2", %{starts_at: afternoon}))
  end
end
