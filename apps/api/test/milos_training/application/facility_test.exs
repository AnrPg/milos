defmodule MilosTraining.Application.FacilityTest do
  use MilosTraining.DataCase, async: false

  alias MilosTraining.Application.{CheckInOpenGym, SubmitBooking}
  alias MilosTraining.{Facility, Finance, Organizations}

  import MilosTraining.TestFixtures

  setup do
    {:ok, organization} = Organizations.ensure_legacy_organization_for_migration()
    Repo.query!("SELECT set_config($1, $2, false)", ["app.organization_id", organization.id])

    admin = admin_fixture()
    context = tenant_context(admin, :owner)

    {:ok, _settings} =
      Finance.update_finance_settings(%{
        entitlement_enforcement_mode: "enforce_managed",
        entitlement_timezone: "Europe/Athens",
        payment_reminder_interval_days: 7
      })

    {:ok, downtown} = Facility.create_location(context, %{name: "Downtown", address: "Main 1"})
    {:ok, harbour} = Facility.create_location(context, %{name: "Harbour"})

    %{admin: admin, context: context, downtown: downtown, harbour: harbour}
  end

  defp tenant_context(actor, role \\ nil) do
    {:ok, _membership} = Organizations.ensure_legacy_membership_for_migration(actor, role)

    {:ok, context} =
      Organizations.resolve_tenant_context(actor, Organizations.legacy_organization_slug())

    context
  end

  defp member_with(package_type, fields) do
    {:ok, package} =
      Finance.create_package(%{
        name: "Package #{System.unique_integer([:positive])}",
        package_type: package_type,
        fields: fields
      })

    user = user_fixture()
    context = tenant_context(user)

    {:ok, membership} =
      Finance.upsert_membership(user.id, %{
        user_type_snapshot: "member",
        status: "active",
        signup_source: "direct"
      })

    {:ok, _subscription} = Finance.assign_package(membership.id, package.id, %{})
    {user, context}
  end

  test "locations are named per organization and archived instead of deleted", %{
    context: context,
    downtown: downtown
  } do
    assert {:error, %Ecto.Changeset{}} = Facility.create_location(context, %{name: "downtown"})

    assert {:ok, %{name: "Downtown East"}} =
             Facility.update_location(context, downtown.id, %{name: " Downtown East "})

    assert {:ok, %{archived_at: %DateTime{}}} = Facility.archive_location(context, downtown.id)
    assert ["Harbour"] == context |> Facility.list_locations() |> Enum.map(& &1.name)

    assert 2 ==
             context |> Facility.list_locations(include_archived: true) |> length()

    assert {:ok, _} = Facility.create_location(context, %{name: "Downtown East"})
  end

  test "a location stores where it is and when it is open (ADR-141)", %{
    context: context,
    harbour: harbour
  } do
    assert {:ok, location} =
             Facility.update_location(context, harbour.id, %{
               "latitude" => 37.9969,
               "longitude" => 23.7349,
               "neighbourhood" => " Κυψέλη ",
               "city" => "Αθήνα",
               "country_code" => "gr",
               "opening_hours" => [
                 %{"weekday" => 6, "opens" => "09:00", "closes" => "13:00"},
                 %{"weekday" => 1, "opens" => "07:00", "closes" => "22:00"}
               ],
               "accessibility" => ["step_free", "showers"]
             })

    assert %{
             latitude: 37.9969,
             longitude: 23.7349,
             neighbourhood: "Κυψέλη",
             country_code: "GR",
             opening_hours: [%{"weekday" => 1}, %{"weekday" => 6}],
             accessibility: ["step_free", "showers"]
           } = location

    assert {:error, %Ecto.Changeset{errors: errors}} =
             Facility.update_location(context, harbour.id, %{
               "latitude" => 37.9,
               "longitude" => nil
             })

    assert Keyword.has_key?(errors, :latitude)

    assert {:error, %Ecto.Changeset{errors: errors}} =
             Facility.update_location(context, harbour.id, %{"accessibility" => ["moat"]})

    assert Keyword.has_key?(errors, :accessibility)

    %{rows: [[distance]]} =
      Repo.query!(
        "SELECT ST_Distance(milos_geo_point(latitude, longitude), milos_geo_point($1, $2)) FROM facility_locations WHERE id = $3",
        [37.9838, 23.7275, Ecto.UUID.dump!(harbour.id)]
      )

    assert_in_delta distance, 1_590, 60
  end

  test "classes at a location outside the package scope cannot be booked", %{
    admin: admin,
    downtown: downtown,
    harbour: harbour
  } do
    workout = workout_fixture(admin)
    {member, context} = member_with("membership", %{"facility.location_ids" => [downtown.id]})

    inside = slot_fixture(workout, %{auto_approve: true, location_id: downtown.id})

    outside =
      slot_fixture(workout, %{
        auto_approve: true,
        location_id: harbour.id,
        scheduled_at: DateTime.add(inside.scheduled_at, 3600)
      })

    assert outside.location_id == harbour.id
    assert {:ok, _booking} = SubmitBooking.call(context, member, inside.id)

    assert {:error, :finance_location_not_included} =
             SubmitBooking.call(context, member, outside.id)
  end

  test "open-gym check-ins consume one visit per day and respect the quota and scope", %{
    admin: admin,
    context: admin_context,
    downtown: downtown,
    harbour: harbour
  } do
    {member, context} =
      member_with("membership", %{
        "facility.open_gym" => true,
        "facility.open_gym_visits" => %{"limit" => 1, "period" => "calendar_month"},
        "facility.location_ids" => [downtown.id]
      })

    assert {:error, :finance_location_not_included} =
             CheckInOpenGym.call(context, member, member.id, %{"location_id" => harbour.id})

    assert {:ok, check_in} =
             CheckInOpenGym.call(context, member, member.id, %{"location_id" => downtown.id})

    assert check_in.source == "self"
    assert check_in.location_name == "Downtown"
    refute check_in.already_checked_in

    assert {:ok, again} = CheckInOpenGym.call(admin_context, admin, member.id, %{})
    assert again.id == check_in.id
    assert again.already_checked_in

    entitlement = Finance.get_effective_entitlement(member.id)
    assert %{committed: 1} = entitlement.allowances[:open_gym_visits]

    [listed] = Facility.list_check_ins(admin_context, %{user_id: member.id})
    assert listed.nickname == member.nickname
  end

  test "staff check-ins need the member's open-gym access", %{
    admin: admin,
    context: admin_context,
    downtown: downtown
  } do
    {member, _context} = member_with("membership", %{})

    assert {:error, _reason, _details} =
             CheckInOpenGym.call(admin_context, admin, member.id, %{})

    {:ok, _archived} = Facility.archive_location(admin_context, downtown.id)

    {open_gym_member, _context} = member_with("membership", %{"facility.open_gym" => true})

    assert {:error, :location_archived} =
             CheckInOpenGym.call(admin_context, admin, open_gym_member.id, %{
               "location_id" => downtown.id
             })

    assert {:ok, %{source: "staff", recorded_by_id: recorded_by}} =
             CheckInOpenGym.call(admin_context, admin, open_gym_member.id, %{})

    assert recorded_by == admin.id
  end
end
