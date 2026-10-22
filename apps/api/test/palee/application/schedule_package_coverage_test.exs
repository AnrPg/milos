defmodule Palee.Application.SchedulePackageCoverageTest do
  use Palee.DataCase, async: false

  alias Palee.Application.{GetScheduleCalendar, SubmitBooking}
  alias Palee.{Finance, Organizations}

  import Palee.TestFixtures

  setup do
    {:ok, legacy_organization} = Organizations.ensure_legacy_organization_for_migration()

    Palee.Repo.query!("SELECT set_config($1, $2, false)", [
      "app.organization_id",
      legacy_organization.id
    ])

    {:ok, _settings} =
      Finance.update_finance_settings(%{
        entitlement_enforcement_mode: "enforce_managed",
        entitlement_timezone: "Europe/Athens",
        payment_reminder_interval_days: 7
      })

    admin = admin_fixture()
    legacy_tenant_context(admin, :owner)
    slot = slot_fixture(workout_fixture(admin), %{auto_approve: true})

    %{slot: slot}
  end

  defp legacy_tenant_context(actor, role \\ nil) do
    {:ok, _membership} = Organizations.ensure_legacy_membership_for_migration(actor, role)

    {:ok, context} =
      Organizations.resolve_tenant_context(actor, Organizations.legacy_organization_slug())

    context
  end

  defp member_with_package(code, params) do
    member = user_fixture()
    context = legacy_tenant_context(member)

    {:ok, package} =
      Finance.create_package(%{
        code: code,
        name: code,
        family: "limited-visits",
        billing_period: "monthly",
        params: Map.put(params, "entitlement_version", 1)
      })

    {:ok, membership} =
      Finance.upsert_membership(member.id, %{
        user_type_snapshot: "member",
        status: "active",
        signup_source: "direct"
      })

    {:ok, _subscription} =
      Finance.assign_package(membership.id, package.id, %{starts_on: gym_today()})

    {member, context}
  end

  defp coverage(context, member, slot_id) do
    {:ok, %{slots: slots}} =
      GetScheduleCalendar.call(context, member, %{
        "start_date" => Date.to_iso8601(gym_today())
      })

    slots |> Enum.find(&(&1.id == slot_id)) |> Map.fetch!(:covered_by_package)
  end

  test "a class is covered by a class package even once its visits are used up", %{slot: slot} do
    {member, context} =
      member_with_package("one_class", %{
        "channels" => ["in_person"],
        "capabilities" => ["book_classes"],
        "allowances" => %{"class_visits" => %{"limit" => 1, "period" => "calendar_month"}}
      })

    assert coverage(context, member, slot.id)
    assert {:ok, _booking} = SubmitBooking.call(context, member, slot.id)
    assert coverage(context, member, slot.id)
  end

  test "a class is not covered by an events-only package", %{slot: slot} do
    {member, context} =
      member_with_package("events_only", %{
        "channels" => ["events"],
        "capabilities" => ["book_events"],
        "allowances" => %{"event_visits" => %{"limit" => 4, "period" => "calendar_month"}}
      })

    refute coverage(context, member, slot.id)
  end

  test "a member without a package sees nothing covered", %{slot: slot} do
    member = user_fixture()
    context = legacy_tenant_context(member)

    refute coverage(context, member, slot.id)
  end

  test "the schedule names the coaches of its classes" do
    admin = admin_fixture()
    context = legacy_tenant_context(admin, :owner)
    coach = user_fixture()
    legacy_tenant_context(coach, :coach)
    slot_fixture(workout_fixture(admin), %{coach_user_id: coach.id})

    {:ok, %{coaches: coaches}} =
      GetScheduleCalendar.call(context, admin, %{
        "start_date" => Date.to_iso8601(gym_today())
      })

    assert [%{id: id, nickname: nickname}] = coaches
    assert id == coach.id
    assert nickname == coach.nickname
  end

  test "the schedule tells a member until when cancelling is free", %{slot: slot} do
    {:ok, package} =
      Finance.create_package(%{
        name: "Cutoff six",
        package_type: "class_pack",
        fields: %{
          "group_classes.visits" => %{"limit" => 8, "period" => "subscription_period"},
          "booking.cancellation_cutoff_hours" => 6
        }
      })

    member = user_fixture()
    context = legacy_tenant_context(member)

    {:ok, membership} =
      Finance.upsert_membership(member.id, %{
        user_type_snapshot: "member",
        status: "active",
        signup_source: "direct"
      })

    {:ok, _subscription} = Finance.assign_package(membership.id, package.id, %{})

    {:ok, %{slots: slots}} =
      GetScheduleCalendar.call(context, member, %{
        "start_date" => Date.to_iso8601(gym_today())
      })

    listed = Enum.find(slots, &(&1.id == slot.id))
    assert listed.cancel_free_until == DateTime.add(listed.scheduled_at, -6 * 3600, :second)
  end

  test "without a cutoff, cancelling stays free", %{slot: slot} do
    member = user_fixture()
    context = legacy_tenant_context(member)

    {:ok, %{slots: slots}} =
      GetScheduleCalendar.call(context, member, %{
        "start_date" => Date.to_iso8601(gym_today())
      })

    assert Enum.find(slots, &(&1.id == slot.id)).cancel_free_until == nil
  end
end
