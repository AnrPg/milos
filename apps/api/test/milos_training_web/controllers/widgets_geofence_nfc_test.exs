defmodule MilosTrainingWeb.WidgetsGeofenceNfcTest do
  @moduledoc """
  ADR-173 (P3-M11): NFC door tags (admin and the tag tap), the arrival
  reminder's regions and its check-in, and the home-screen widget token,
  snapshot and «+1 νερό».
  """

  use MilosTrainingWeb.ConnCase, async: false

  import MilosTraining.TestFixtures

  alias MilosTraining.{Facility, Finance, Organizations, Repo, Scheduling}

  setup do
    {:ok, organization} =
      Organizations.create_organization(%{name: "Tag Box #{System.unique_integer([:positive])}"})

    Repo.query!("SELECT set_config($1, $2, false)", ["app.organization_id", organization.id])

    owner = user_fixture()
    add_member(organization, owner, :owner)
    {:ok, context} = Organizations.resolve_tenant_context(owner, organization.slug)

    {:ok, _settings} =
      Finance.update_finance_settings(%{
        entitlement_enforcement_mode: "enforce_managed",
        entitlement_timezone: "Europe/Athens",
        payment_reminder_interval_days: 7
      })

    {:ok, location} =
      Facility.create_location(context, %{
        name: "Κεντρικό",
        address: "Οδός 1",
        city: "Αθήνα",
        latitude: 37.9838,
        longitude: 23.7275
      })

    _class_type = class_type_fixture(%{tenant_context: context})
    workout = workout_fixture(owner, %{tenant_context: context, title: "Tag WOD"})

    %{
      organization: organization,
      owner: owner,
      context: context,
      location: location,
      workout: workout,
      admin: "/api/org/#{organization.slug}/admin/check-in"
    }
  end

  defp add_member(organization, user, role \\ :member) do
    {:ok, _membership} =
      Organizations.add_membership(%{
        organization_id: organization.id,
        user_id: user.id,
        role: role,
        status: :active,
        joined_at: DateTime.utc_now()
      })

    user
  end

  defp member(ctx), do: add_member(ctx.organization, user_fixture())

  defp slot(ctx, minutes_from_now, attrs \\ %{}) do
    slot_fixture(
      ctx.workout,
      Map.merge(
        %{
          tenant_context: ctx.context,
          auto_approve: true,
          location_id: ctx.location.id,
          scheduled_at:
            DateTime.utc_now()
            |> DateTime.add(minutes_from_now * 60)
            |> DateTime.truncate(:second)
        },
        attrs
      )
    )
  end

  defp book(ctx, user, slot) do
    {:ok, context} = Organizations.resolve_tenant_context(user, ctx.organization.slug)
    {:ok, booking} = Scheduling.submit_auto_approved_booking(context, user.id, slot.id)
    booking
  end

  defp scan(user, body),
    do: build_conn() |> put_bearer_token(user) |> post("/api/check-in/scan", body)

  defp as_owner(ctx), do: build_conn() |> put_bearer_token(ctx.owner)

  # Etc/GMT names flip the sign: "Etc/GMT-3" is UTC+3.
  defp midday_zone do
    case 12 - DateTime.utc_now().hour do
      0 -> "Etc/UTC"
      offset when offset > 0 -> "Etc/GMT-#{offset}"
      offset -> "Etc/GMT+#{-offset}"
    end
  end

  # ------------------------------------------------------------------ NFC

  describe "NFC door tag" do
    defp tag(ctx),
      do:
        ctx |> as_owner() |> get("#{ctx.admin}/door/#{ctx.location.id}/nfc") |> json_response(200)

    defp set_tag(ctx, enabled) do
      ctx
      |> as_owner()
      |> put("#{ctx.admin}/door/#{ctx.location.id}/nfc", %{enabled: enabled})
      |> json_response(200)
    end

    defp tap(ctx, user, code), do: scan(user, %{location_id: ctx.location.id, nfc_code: code})

    test "works only while on, checks in bookings only, and dies when rotated", ctx do
      %{"enabled" => false, "code" => code, "deep_link" => link} = tag(ctx)
      assert link =~ "/c/#{ctx.location.id}/n/#{code}"
      assert code == tag(ctx)["code"]

      user = member(ctx)
      class = slot(ctx, 10)
      book(ctx, user, class)

      assert %{"code" => "invalid_door_code"} = tap(ctx, user, code) |> json_response(422)
      assert %{"enabled" => true} = set_tag(ctx, true)

      assert %{
               "outcome" => "checked_in",
               "check_in" => %{"kind" => "class", "method" => "door_nfc"}
             } =
               tap(ctx, user, code) |> json_response(200)

      assert %{check_in_method: "door_nfc"} =
               Scheduling.get_attendance_for_user_class(ctx.context, user.id, class.id)

      other = member(ctx)

      assert %{"outcome" => "no_booking", "membership" => "member"} =
               tap(ctx, other, code) |> json_response(200)

      assert [] = Facility.list_check_ins(ctx.context, %{user_id: other.id})

      # The poster's code is not the tag's.
      poster =
        ctx
        |> as_owner()
        |> get("#{ctx.admin}/door/#{ctx.location.id}/poster")
        |> json_response(200)

      assert %{"code" => "invalid_door_code"} =
               tap(ctx, other, poster["code"]) |> json_response(422)

      rotated =
        ctx
        |> as_owner()
        |> post("#{ctx.admin}/door/#{ctx.location.id}/nfc/rotate")
        |> json_response(200)

      refute rotated["code"] == code
      assert %{"code" => "invalid_door_code"} = tap(ctx, other, code) |> json_response(422)

      build_conn()
      |> put_bearer_token(user)
      |> put("#{ctx.admin}/door/#{ctx.location.id}/nfc", %{enabled: false})
      |> json_response(403)
    end
  end

  # ------------------------------------------------------------------ geofence

  describe "arrival reminder" do
    defp geofences(user),
      do: build_conn() |> put_bearer_token(user) |> get("/api/me/check-in/geofences")

    test "lists located bookings with their windows and checks in from the token", ctx do
      user = member(ctx)
      class = slot(ctx, 20)
      booking = book(ctx, user, class)

      assert %{"regions" => [region], "valid_until" => _} =
               geofences(user) |> json_response(200)

      assert %{
               "location_id" => location_id,
               "box_name" => _,
               "latitude" => 37.9838,
               "radius_m" => 150,
               "token" => token,
               "windows" => [%{"booking_id" => booking_id}]
             } = region

      assert location_id == ctx.location.id
      assert booking_id == booking.id

      # Someone else's token is refused.
      assert %{"code" => "invalid_door_code"} =
               scan(member(ctx), %{geofence_token: token}) |> json_response(422)

      assert %{"outcome" => "checked_in", "check_in" => %{"method" => "geofence"}} =
               scan(user, %{geofence_token: token}) |> json_response(200)

      # Checked in: nothing left to remind about.
      assert %{"regions" => []} = geofences(user) |> json_response(200)
    end

    test "nothing without a booking, a map point or the owner's rule", ctx do
      user = member(ctx)
      assert %{"regions" => []} = geofences(user) |> json_response(200)

      book(ctx, user, slot(ctx, 20))
      assert %{"regions" => [%{"token" => token}]} = geofences(user) |> json_response(200)

      ctx
      |> as_owner()
      |> put("#{ctx.admin}/settings", %{geofence_reminder: false})
      |> json_response(200)
      |> then(&assert(&1["settings"]["geofence_reminder"] == false))

      assert %{"regions" => []} = geofences(user) |> json_response(200)

      assert %{"code" => "invalid_door_code"} =
               scan(user, %{geofence_token: token}) |> json_response(422)
    end
  end

  # ------------------------------------------------------------------ widgets

  describe "widgets" do
    defp issue(user, body \\ %{platform: "ios"}) do
      build_conn() |> put_bearer_token(user) |> post("/api/me/widget-tokens", body)
    end

    defp widget(token) do
      build_conn()
      |> put_req_header("authorization", "Bearer " <> token)
      |> put_req_header("content-type", "application/json")
    end

    test "a token reads the snapshot, adds water and dies when revoked or replaced", ctx do
      user = member(ctx)
      book(ctx, user, slot(ctx, 60))

      %{"id" => id, "token" => token} = issue(user) |> json_response(201)

      # A zone where it is about noon now, so the class an hour away is still
      # "today" there whatever time the suite runs.
      snapshot = token |> widget() |> get("/api/widget/snapshot", %{timezone: midday_zone()})

      assert %{
               "water" => %{"ml" => 0, "glass_ml" => 250, "can_add" => false},
               "next_class" => %{"kind" => "class"},
               "today" => [_ | _]
             } = json_response(snapshot, 200)

      # Water needs the health-data consent, given in the app.
      assert %{"code" => "health_data_consent_required"} =
               token
               |> widget()
               |> post("/api/widget/water", %{timezone: "UTC"})
               |> json_response(403)

      build_conn()
      |> put_bearer_token(user)
      |> put("/api/me/body/consents/health_data")
      |> json_response(200)

      assert %{"water" => %{"ml" => 250, "count" => 1, "can_add" => true}} =
               token
               |> widget()
               |> post("/api/widget/water", %{timezone: "Europe/Athens"})
               |> json_response(200)

      # The session token is not a widget token, and vice versa.
      assert %{"code" => "invalid_widget_token"} =
               build_conn()
               |> put_bearer_token(user)
               |> get("/api/widget/snapshot")
               |> json_response(401)

      # A new token for the install replaces the old one.
      %{"token" => fresh, "id" => fresh_id} =
        issue(user, %{platform: "ios", replaces_id: id}) |> json_response(201)

      assert token |> widget() |> get("/api/widget/snapshot") |> json_response(401)
      assert fresh |> widget() |> get("/api/widget/snapshot") |> json_response(200)

      build_conn()
      |> put_bearer_token(user)
      |> delete("/api/me/widget-tokens/#{fresh_id}")
      |> response(204)

      assert fresh |> widget() |> get("/api/widget/snapshot") |> json_response(401)
    end

    test "another person cannot revoke a token and junk is refused", ctx do
      user = member(ctx)
      %{"id" => id, "token" => token} = issue(user) |> json_response(201)

      build_conn()
      |> put_bearer_token(member(ctx))
      |> delete("/api/me/widget-tokens/#{id}")
      |> json_response(404)

      assert token |> widget() |> get("/api/widget/snapshot") |> json_response(200)
      assert "junk" |> widget() |> get("/api/widget/snapshot") |> json_response(401)
      assert build_conn() |> get("/api/widget/snapshot") |> json_response(401)
      assert issue(user, %{platform: "windows"}) |> json_response(422)
    end
  end
end
