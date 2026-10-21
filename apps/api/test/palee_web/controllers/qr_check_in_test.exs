defmodule PaleeWeb.QrCheckInTest do
  @moduledoc """
  ADR-155 (P2-M7): the door display and its rotating code, the member's door
  scan (booking, choice, idempotency, undo, open gym, suggestions, visitor
  with trials), the desk scan of a personal QR (problems, auto, override),
  the owner's check-in rules and the live desk channel.
  """

  use PaleeWeb.ConnCase, async: false

  import Ecto.Query
  import Palee.TestFixtures
  require Phoenix.ChannelTest

  alias Palee.Application.{PublishBoxPublicProfile, UpdateBoxPublicProfile}
  alias Palee.{Facility, Finance, Organizations, Repo, Scheduling, Trials}
  alias Palee.Infrastructure.Auth.Guardian
  alias PaleeWeb.{CheckInChannel, UserSocket}

  @endpoint PaleeWeb.Endpoint

  setup do
    {:ok, organization} =
      Organizations.create_organization(%{name: "Door Box #{System.unique_integer([:positive])}"})

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
      Facility.create_location(context, %{name: "Κεντρικό", address: "Οδός 1", city: "Αθήνα"})

    _class_type = class_type_fixture(%{tenant_context: context})
    workout = workout_fixture(owner, %{tenant_context: context, title: "Door WOD"})

    %{
      organization: organization,
      owner: owner,
      context: context,
      location: location,
      workout: workout,
      admin: "/api/org/#{organization.slug}/admin/check-in"
    }
  end

  # ------------------------------------------------------------------ helpers

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

  defp member(ctx, fields \\ nil) do
    user = add_member(ctx.organization, user_fixture())

    if fields do
      {:ok, package} =
        Finance.create_package(%{
          name: "Package #{System.unique_integer([:positive])}",
          package_type: "membership",
          fields: fields
        })

      {:ok, membership} =
        Finance.upsert_membership(user.id, %{
          user_type_snapshot: "member",
          status: "active",
          signup_source: "direct"
        })

      {:ok, _subscription} = Finance.assign_package(membership.id, package.id, %{})
    end

    user
  end

  @open_gym %{
    "facility.open_gym" => true,
    "facility.open_gym_visits" => %{"limit" => 1, "period" => "calendar_month"}
  }

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

  defp door(ctx) do
    build_conn()
    |> put_bearer_token(ctx.owner)
    |> get("#{ctx.admin}/door/#{ctx.location.id}")
    |> json_response(200)
  end

  defp scan(user, body) do
    build_conn() |> put_bearer_token(user) |> post("/api/check-in/scan", body)
  end

  defp scan_door(ctx, user, extra \\ %{}) do
    scan(user, Map.merge(%{location_id: ctx.location.id, code: door(ctx)["code"]}, extra))
  end

  defp put_rules(ctx, rules) do
    build_conn()
    |> put_bearer_token(ctx.owner)
    |> put("#{ctx.admin}/settings", rules)
    |> json_response(200)
  end

  # ------------------------------------------------------------------ door display

  describe "door display" do
    test "shows the code, its deep link, the offline batch and the next class", ctx do
      class = slot(ctx, 20)
      display = door(ctx)

      assert display["code"] =~ ~r/\A[A-Za-z0-9_-]{16}\z/
      assert display["deep_link"] =~ "/c/#{ctx.location.id}/#{display["code"]}"
      assert display["rotation_seconds"] == 30
      assert display["seconds_until_rotation"] in 1..30
      assert display["topic"] == "check_in:#{ctx.organization.id}"
      assert display["location"]["name"] == "Κεντρικό"
      assert length(display["codes"]) == 4
      assert hd(display["codes"])["code"] == display["code"]
      assert display["next_class"]["id"] == class.id
      assert display["next_class"]["spots_remaining"] == 10
      assert display["recent_check_ins"] == []
    end

    test "rotating the door secret kills the old code", ctx do
      user = member(ctx, @open_gym)
      old = door(ctx)["code"]

      rotated =
        build_conn()
        |> put_bearer_token(ctx.owner)
        |> post("#{ctx.admin}/door/#{ctx.location.id}/rotate")
        |> json_response(200)

      refute rotated["code"] == old
      assert rotated["rotated_at"]

      assert %{"code" => "invalid_door_code"} =
               scan(user, %{location_id: ctx.location.id, code: old}) |> json_response(422)

      assert %{"outcome" => "checked_in"} =
               scan(user, %{location_id: ctx.location.id, code: rotated["code"]})
               |> json_response(200)
    end

    test "only staff with check-in see the door; nobody can scan a made-up code", ctx do
      user = member(ctx)

      build_conn()
      |> put_bearer_token(user)
      |> get("#{ctx.admin}/door/#{ctx.location.id}")
      |> json_response(403)

      assert %{"code" => "invalid_door_code"} =
               scan(user, %{location_id: ctx.location.id, code: "AAAAAAAAAAAAAAAA"})
               |> json_response(422)

      assert %{"code" => "invalid_door_code"} =
               scan(user, %{location_id: Ecto.UUID.generate(), code: door(ctx)["code"]})
               |> json_response(422)
    end
  end

  # ------------------------------------------------------------------ door scan

  describe "member door scan" do
    test "checks in to the booking in the window, once, and the check-in can be undone", ctx do
      user = member(ctx)
      class = slot(ctx, 10)
      booking = book(ctx, user, class)

      first = scan_door(ctx, user) |> json_response(200)

      assert %{
               "outcome" => "checked_in",
               "check_in" => %{
                 "kind" => "class",
                 "method" => "door_qr",
                 "booking" => %{"id" => id}
               },
               "undo_token" => undo_token,
               "undo_until" => _,
               "box" => %{"slug" => slug}
             } = first

      assert id == booking.id
      assert slug == ctx.organization.slug

      assert %{"outcome" => "already_checked_in", "check_in" => %{"kind" => "class"}} =
               scan_door(ctx, user) |> json_response(200)

      assert %{status: "attended", check_in_method: "door_qr"} =
               Scheduling.get_attendance_for_user_class(ctx.context, user.id, class.id)

      # Someone else cannot use the undo link.
      build_conn()
      |> put_bearer_token(member(ctx))
      |> delete("/api/check-in/scan/#{undo_token}")
      |> json_response(404)

      assert %{"kind" => "class", "id" => _, "package" => _} =
               build_conn()
               |> put_bearer_token(user)
               |> delete("/api/check-in/scan/#{undo_token}")
               |> json_response(200)

      assert nil == Scheduling.get_attendance_for_user_class(ctx.context, user.id, class.id)

      assert %{"outcome" => "checked_in"} = scan_door(ctx, user) |> json_response(200)

      assert %{"code" => "invalid_undo_token"} =
               build_conn()
               |> put_bearer_token(user)
               |> delete("/api/check-in/scan/not-a-token")
               |> json_response(422)
    end

    test "undoing a trial seat's check-in takes the trial back to its previous status", ctx do
      box = %{organization_id: ctx.organization.id}

      trial_for = fn user, status ->
        class = slot(ctx, 10)
        booking = book(ctx, user, class)

        {:ok, request} =
          Trials.insert_request(box, %{
            organization_id: ctx.organization.id,
            user_id: user.id,
            scheduled_class_id: class.id,
            booking_id: booking.id,
            status: "booked",
            source: "qr_door",
            class_starts_at: class.scheduled_at
          })

        request =
          if status == "no_show" do
            {:ok, missed} = Trials.transition(box, request, :no_show, DateTime.utc_now())
            missed
          else
            request
          end

        request
      end

      undo = fn user, token ->
        build_conn()
        |> put_bearer_token(user)
        |> delete("/api/check-in/scan/#{token}")
        |> json_response(200)
      end

      # booked -> attended by the scan -> booked again by the undo.
      user = member(ctx)
      request = trial_for.(user, "booked")
      assert %{"undo_token" => token} = scan_door(ctx, user) |> json_response(200)
      assert %{status: "attended"} = Trials.get_request(box, request.id)
      undo.(user, token)
      assert %{status: "booked", attended_at: nil} = Trials.get_request(box, request.id)

      # A trial marked «Δεν ήρθε» before the scan goes back to no_show.
      other = member(ctx)
      missed = trial_for.(other, "no_show")
      assert %{"undo_token" => token} = scan_door(ctx, other) |> json_response(200)
      assert %{status: "attended"} = Trials.get_request(box, missed.id)
      undo.(other, token)
      assert %{status: "no_show"} = Trials.get_request(box, missed.id)

      # A trial converted in the meantime keeps its conversion.
      third = member(ctx)
      converting = trial_for.(third, "booked")
      assert %{"undo_token" => token} = scan_door(ctx, third) |> json_response(200)

      {:ok, _converted} =
        Trials.transition(
          box,
          Trials.get_request(box, converting.id),
          :convert,
          DateTime.utc_now()
        )

      undo.(third, token)

      assert %{status: "converted", converted_at: %DateTime{}} =
               Trials.get_request(box, converting.id)
    end

    test "the window follows the owner's rules", ctx do
      user = member(ctx)
      book(ctx, user, slot(ctx, 50))

      assert %{"outcome" => "nothing"} = scan_door(ctx, user) |> json_response(200)

      put_rules(ctx, %{window_before_minutes: 60})
      assert %{"outcome" => "checked_in"} = scan_door(ctx, user) |> json_response(200)
    end

    test "several bookings in the window: the person picks with the scan token", ctx do
      user = member(ctx)
      early = book(ctx, user, slot(ctx, 5))
      late = book(ctx, user, slot(ctx, 25))

      assert %{"outcome" => "choose", "choices" => choices, "scan_token" => token} =
               scan_door(ctx, user) |> json_response(200)

      assert Enum.map(choices, & &1["id"]) == [early.id, late.id]

      assert %{"outcome" => "checked_in", "check_in" => %{"booking" => %{"id" => id}}} =
               scan(user, %{scan_token: token, booking_id: late.id}) |> json_response(200)

      assert id == late.id

      assert %{"code" => "invalid_scan_token"} =
               scan(member(ctx), %{scan_token: token, booking_id: late.id}) |> json_response(422)

      assert %{"code" => "booking_not_in_window"} =
               scan(user, %{scan_token: token, booking_id: Ecto.UUID.generate()})
               |> json_response(422)
    end

    test "open gym when the package covers it; undo gives the visit back", ctx do
      user = member(ctx, @open_gym)

      assert %{
               "outcome" => "checked_in",
               "check_in" => %{"kind" => "open_gym", "method" => "door_qr"},
               "undo_token" => undo_token,
               "package" => %{"open_gym_visits_left" => 0}
             } = scan_door(ctx, user) |> json_response(200)

      assert %{"outcome" => "already_checked_in", "check_in" => %{"kind" => "open_gym"}} =
               scan_door(ctx, user) |> json_response(200)

      assert [%{method: "door_qr"}] = Facility.list_check_ins(ctx.context, %{user_id: user.id})

      assert %{"package" => %{"open_gym_visits_left" => 1}} =
               build_conn()
               |> put_bearer_token(user)
               |> delete("/api/check-in/scan/#{undo_token}")
               |> json_response(200)

      assert [] = Facility.list_check_ins(ctx.context, %{user_id: user.id})

      # The single visit of the month is free again.
      assert %{"outcome" => "checked_in"} = scan_door(ctx, user) |> json_response(200)
    end

    test "without a booking or open gym: classes starting soon with spots", ctx do
      user = member(ctx)
      soon = slot(ctx, 60)
      _full = slot(ctx, 70, %{capacity: 1}) |> tap(&book(ctx, member(ctx), &1))
      mine = slot(ctx, 240)
      book(ctx, user, mine)

      assert %{"outcome" => "nothing", "classes" => classes, "next_booking" => next} =
               scan_door(ctx, user) |> json_response(200)

      assert Enum.map(classes, & &1["id"]) == [soon.id]
      assert next["scheduled_class_id"] == mine.id
    end

    test "open gym for any member when the owner doesn't require a package", ctx do
      user = member(ctx)
      put_rules(ctx, %{open_gym_requires_package: false})

      assert %{"outcome" => "checked_in", "check_in" => %{"kind" => "open_gym"}} =
               scan_door(ctx, user) |> json_response(200)
    end
  end

  # ------------------------------------------------------------------ visitors

  describe "non-member scan" do
    test "sees the box and is kept for the desk; a published box offers trials", ctx do
      visitor = user_fixture()
      trial_class = slot(ctx, 120)

      assert %{
               "outcome" => "visitor",
               "membership" => "none",
               "trial" => nil,
               "follow" => _,
               "box" => %{"slug" => slug}
             } = scan_door(ctx, visitor) |> json_response(200)

      assert slug == ctx.organization.slug

      {:ok, profile} =
        UpdateBoxPublicProfile.call(ctx.context, %{
          "about" => "Καλώς ήρθες.",
          "disciplines" => ["crossfit"],
          "audiences" => [],
          "amenities" => [],
          "languages" => ["el", "en"]
        })

      {:ok, _} =
        PublishBoxPublicProfile.publish(ctx.context, %{"lock_version" => profile.lock_version})

      {:ok, _policy} = Trials.update_policy(ctx.context, %{enabled: true})

      assert %{"outcome" => "visitor", "trial" => %{"enabled" => true, "classes" => classes}} =
               scan_door(ctx, visitor) |> json_response(200)

      assert [%{"id" => id, "trial_seats" => seats}] = classes
      assert id == trial_class.id
      assert seats > 0

      put_rules(ctx, %{visitor_trial_offer: false})
      assert %{"trial" => nil} = scan_door(ctx, visitor) |> json_response(200)

      assert %{"visitors" => visitors} =
               build_conn()
               |> put_bearer_token(ctx.owner)
               |> get("#{ctx.admin}/visitors")
               |> json_response(200)

      assert length(visitors) == 3
      assert Enum.all?(visitors, &(&1["user_id"] == visitor.id))
      assert Enum.any?(visitors, & &1["trial_offered"])
    end
  end

  # ------------------------------------------------------------------ desk

  describe "desk scan of a personal QR" do
    defp my_code(ctx, user) do
      build_conn()
      |> put_bearer_token(user)
      |> get("/api/org/#{ctx.organization.slug}/me/check-in/code")
      |> json_response(200)
    end

    defp desk_scan(ctx, body) do
      build_conn()
      |> put_bearer_token(ctx.owner)
      |> post("#{ctx.admin}/scan-member", body)
    end

    test "the personal code rotates every 30 seconds and names the member", ctx do
      user = member(ctx, @open_gym)

      assert %{"code" => "M1" <> _ = code, "rotation_seconds" => 30, "expires_at" => _} =
               my_code(ctx, user)

      assert %{
               "member" => %{"id" => id},
               "method" => "member_qr",
               "decision" => "open_gym",
               "problems" => [],
               "can_auto_check_in" => true,
               "checked_in" => nil,
               "package" => %{"status" => "active"}
             } = desk_scan(ctx, %{code: code, location_id: ctx.location.id}) |> json_response(200)

      assert id == user.id
    end

    test "auto checks in when all is fine", ctx do
      user = member(ctx)
      booking = book(ctx, user, slot(ctx, 2))
      code = my_code(ctx, user)["code"]

      assert %{"checked_in" => %{"kind" => "class", "method" => "member_qr"}, "bookings" => [b]} =
               desk_scan(ctx, %{code: code, location_id: ctx.location.id, auto: true})
               |> json_response(200)

      assert b["id"] == booking.id

      assert %{"decision" => "already_checked_in", "already_checked_in" => "class"} =
               desk_scan(ctx, %{code: code, location_id: ctx.location.id, auto: true})
               |> json_response(200)
    end

    test "problems block auto; override only when the owner allows it", ctx do
      user = member(ctx)
      code = my_code(ctx, user)["code"]

      assert %{
               "problems" => problems,
               "can_auto_check_in" => false,
               "override_allowed" => false,
               "checked_in" => nil
             } =
               desk_scan(ctx, %{code: code, location_id: ctx.location.id, auto: true})
               |> json_response(200)

      assert "nothing_to_check_in" in problems

      path = "#{ctx.admin}/members/#{user.id}"
      body = %{method: "member_qr", location_id: ctx.location.id}

      assert %{"code" => "check_in_problems"} =
               build_conn()
               |> put_bearer_token(ctx.owner)
               |> post(path, body)
               |> json_response(409)

      assert %{"code" => "override_not_allowed"} =
               build_conn()
               |> put_bearer_token(ctx.owner)
               |> post(path, Map.put(body, :override, true))
               |> json_response(403)

      put_rules(ctx, %{desk_override: true})

      assert %{"override_allowed" => true} =
               desk_scan(ctx, %{code: code, location_id: ctx.location.id}) |> json_response(200)

      assert %{
               "checked_in" => %{
                 "kind" => "open_gym",
                 "override" => true,
                 "method" => "member_qr"
               }
             } =
               build_conn()
               |> put_bearer_token(ctx.owner)
               |> post(path, Map.put(body, :override, true))
               |> json_response(200)

      assert [%{method: "member_qr"}] = Facility.list_check_ins(ctx.context, %{user_id: user.id})
    end

    test "desk search checks a member in by hand", ctx do
      user = member(ctx, @open_gym)

      assert %{"checked_in" => %{"kind" => "open_gym", "method" => "desk_search"}} =
               build_conn()
               |> put_bearer_token(ctx.owner)
               |> post("#{ctx.admin}/members/#{user.id}", %{location_id: ctx.location.id})
               |> json_response(200)
    end

    test "codes of other boxes, made-up codes and non-members are refused", ctx do
      outsider = user_fixture()

      {:ok, other} =
        Organizations.create_organization(%{name: "Other #{System.unique_integer([:positive])}"})

      add_member(other, outsider)

      foreign =
        build_conn()
        |> put_bearer_token(outsider)
        |> get("/api/org/#{other.slug}/me/check-in/code")
        |> json_response(200)

      assert %{"code" => "invalid_member_code"} =
               desk_scan(ctx, %{code: foreign["code"]}) |> json_response(422)

      assert %{"code" => "invalid_member_code"} =
               desk_scan(ctx, %{code: "M1garbage"}) |> json_response(422)

      # A valid code of this box for someone who is no longer a member.
      former = member(ctx)
      code = my_code(ctx, former)["code"]

      Repo.query!(
        "UPDATE organization_memberships SET status = 'revoked' WHERE user_id = $1",
        [Ecto.UUID.dump!(former.id)]
      )

      assert %{"code" => "not_a_member"} = desk_scan(ctx, %{code: code}) |> json_response(422)
    end
  end

  # ------------------------------------------------------------------ settings

  describe "check-in rules" do
    test "defaults, validation and staff access", ctx do
      path = "#{ctx.admin}/settings"

      assert %{
               "settings" => %{
                 "window_before_minutes" => 30,
                 "window_after_minutes" => 15,
                 "open_gym_requires_package" => true,
                 "visitor_trial_offer" => true,
                 "desk_override" => false,
                 "door_rotation_seconds" => 30
               }
             } = build_conn() |> put_bearer_token(ctx.owner) |> get(path) |> json_response(200)

      assert %{"errors" => [_ | _]} =
               build_conn()
               |> put_bearer_token(ctx.owner)
               |> put(path, %{door_rotation_seconds: 20})
               |> json_response(422)

      assert %{"settings" => %{"door_rotation_seconds" => 60, "window_before_minutes" => 30}} =
               put_rules(ctx, %{door_rotation_seconds: 60})

      assert %{"rotation_seconds" => 60, "codes" => codes} = door(ctx)
      assert length(codes) == 2

      build_conn() |> put_bearer_token(member(ctx)) |> get(path) |> json_response(403)
    end
  end

  # ------------------------------------------------------------------ poster

  describe "printed poster" do
    defp poster(ctx) do
      build_conn()
      |> put_bearer_token(ctx.owner)
      |> get("#{ctx.admin}/door/#{ctx.location.id}/poster")
      |> json_response(200)
    end

    defp set_poster(ctx, enabled) do
      build_conn()
      |> put_bearer_token(ctx.owner)
      |> put("#{ctx.admin}/door/#{ctx.location.id}/poster", %{enabled: enabled})
      |> json_response(200)
    end

    defp scan_poster(ctx, user, code),
      do: scan(user, %{location_id: ctx.location.id, poster_code: code})

    test "works only while on, checks in bookings only, and dies when rotated", ctx do
      %{"enabled" => false, "code" => code, "deep_link" => link} = poster(ctx)
      assert link =~ "/c/#{ctx.location.id}/p/#{code}"
      assert code == poster(ctx)["code"]

      user = member(ctx, @open_gym)
      class = slot(ctx, 10)
      book(ctx, user, class)

      assert %{"code" => "invalid_door_code"} = scan_poster(ctx, user, code) |> json_response(422)

      assert %{"enabled" => true} = set_poster(ctx, true)

      assert %{
               "outcome" => "checked_in",
               "check_in" => %{"kind" => "class", "method" => "door_poster"}
             } =
               scan_poster(ctx, user, code) |> json_response(200)

      assert %{check_in_method: "door_poster"} =
               Scheduling.get_attendance_for_user_class(ctx.context, user.id, class.id)

      # No booking: never open gym, even with a package that covers it.
      other = member(ctx, @open_gym)

      assert %{"outcome" => "no_booking", "membership" => "member"} =
               scan_poster(ctx, other, code) |> json_response(200)

      assert [] = Facility.list_check_ins(ctx.context, %{user_id: other.id})

      # A visitor sees «not a member» and no trial offer.
      {:ok, _policy} = Trials.update_policy(ctx.context, %{enabled: true})

      assert %{"outcome" => "visitor", "membership" => "none", "trial" => nil} =
               scan_poster(ctx, user_fixture(), code) |> json_response(200)

      rotated =
        build_conn()
        |> put_bearer_token(ctx.owner)
        |> post("#{ctx.admin}/door/#{ctx.location.id}/poster/rotate")
        |> json_response(200)

      refute rotated["code"] == code

      assert %{"code" => "invalid_door_code"} =
               scan_poster(ctx, other, code) |> json_response(422)

      # The poster code is not a door code and vice versa.
      assert %{"code" => "invalid_door_code"} =
               scan(other, %{location_id: ctx.location.id, code: rotated["code"]})
               |> json_response(422)

      set_poster(ctx, false)

      assert %{"code" => "invalid_door_code"} =
               scan_poster(ctx, other, rotated["code"]) |> json_response(422)

      build_conn()
      |> put_bearer_token(user)
      |> put("#{ctx.admin}/door/#{ctx.location.id}/poster", %{enabled: true})
      |> json_response(403)
    end

    test "several bookings from the poster: the pick stays a poster check-in", ctx do
      user = member(ctx)
      set_poster(ctx, true)
      _early = book(ctx, user, slot(ctx, 5))
      late = book(ctx, user, slot(ctx, 25))

      assert %{"outcome" => "choose", "scan_token" => token} =
               scan_poster(ctx, user, poster(ctx)["code"]) |> json_response(200)

      assert %{"check_in" => %{"method" => "door_poster"}} =
               scan(user, %{scan_token: token, booking_id: late.id}) |> json_response(200)
    end
  end

  # ------------------------------------------------------------------ staff notice

  describe "visitor notification" do
    defp visitor_notices(user_id) do
      Repo.all(
        from n in Palee.Notifications.Notification,
          where: n.user_id == ^user_id and n.type == :check_in_visitor
      )
    end

    test "staff who check people in hear about a visitor, once an hour", ctx do
      coach = add_member(ctx.organization, user_fixture(), :coach)
      plain = member(ctx)
      visitor = user_fixture()

      scan_door(ctx, visitor) |> json_response(200)
      scan_door(ctx, visitor) |> json_response(200)

      assert [notice] = visitor_notices(ctx.owner.id)
      assert notice.payload["visitor_id"] == visitor.id
      assert notice.payload["box_name"]
      assert notice.payload["trial_available"] in [false, "false"]
      assert notice.payload["url"] =~ "/admin/check-in?visitor="
      assert [] = visitor_notices(plain.id)

      # A coach is notified only when their role carries check-in.
      coach_can? =
        ctx.organization.id
        |> Organizations.list_user_ids_with_capability(:check_in)
        |> Enum.member?(coach.id)

      assert length(visitor_notices(coach.id)) == if(coach_can?, do: 1, else: 0)

      # Another visitor is a new notice.
      scan_door(ctx, user_fixture()) |> json_response(200)
      assert length(visitor_notices(ctx.owner.id)) == 2
    end

    test "the notice says when trials are open", ctx do
      {:ok, _policy} = Trials.update_policy(ctx.context, %{enabled: true})
      scan_door(ctx, user_fixture()) |> json_response(200)

      assert [%{payload: %{"trial_available" => available}}] = visitor_notices(ctx.owner.id)
      assert available in [true, "true"]
    end
  end

  # ------------------------------------------------------------------ code modes

  describe "personal code mode" do
    defp code_of(ctx, user) do
      build_conn()
      |> put_bearer_token(user)
      |> get("/api/org/#{ctx.organization.slug}/me/check-in/code")
      |> json_response(200)
    end

    defp desk(ctx, code) do
      build_conn()
      |> put_bearer_token(ctx.owner)
      |> post("#{ctx.admin}/scan-member", %{code: code, location_id: ctx.location.id})
    end

    defp reset_code(ctx, user) do
      build_conn()
      |> put_bearer_token(user)
      |> post("/api/org/#{ctx.organization.slug}/me/check-in/code/reset")
    end

    test "rotating by default: no Wallet, nothing to reset", ctx do
      user = member(ctx)

      assert %{
               "mode" => "rotating",
               "code" => "M1" <> _,
               "wallet_available" => false,
               "rotation_seconds" => 30
             } =
               code_of(ctx, user)

      assert %{"code" => "wallet_requires_static_code"} =
               build_conn()
               |> put_bearer_token(user)
               |> post("/api/org/#{ctx.organization.slug}/me/wallet-passes", %{platform: "apple"})
               |> json_response(409)

      assert %{"code" => "member_code_not_static"} = reset_code(ctx, user) |> json_response(409)
    end

    test "static codes persist, scan at the desk, reset, revoke and end with the mode", ctx do
      user = member(ctx, @open_gym)
      put_rules(ctx, %{member_code_mode: "static"})

      assert %{
               "mode" => "static",
               "code" => "S1" <> _ = code,
               "wallet_available" => true,
               "rotation_seconds" => nil
             } =
               code_of(ctx, user)

      assert code_of(ctx, user)["code"] == code

      assert %{"method" => "member_qr", "member" => %{"id" => id}} =
               desk(ctx, code) |> json_response(200)

      assert id == user.id

      # A rotating code still works at the desk in static mode.
      key = Palee.Application.CheckInKeys.member_key(ctx.organization.id)

      rotating =
        Palee.Facility.Domain.MemberCode.current(key, user.id, DateTime.utc_now()).code

      assert %{"method" => "member_qr"} = desk(ctx, rotating) |> json_response(200)

      # The member resets: the old code stops, a new one works.
      assert %{"code" => new_code} = reset_code(ctx, user) |> json_response(200)
      refute new_code == code
      assert %{"code" => "member_code_revoked"} = desk(ctx, code) |> json_response(422)
      assert %{"method" => "member_qr"} = desk(ctx, new_code) |> json_response(200)

      # Staff revoke it.
      assert %{"revoked_codes" => 1} =
               build_conn()
               |> put_bearer_token(ctx.owner)
               |> delete("#{ctx.admin}/members/#{user.id}/code")
               |> json_response(200)

      assert %{"code" => "member_code_revoked"} = desk(ctx, new_code) |> json_response(422)

      # A fresh code is issued lazily; going back to rotating ends it.
      third = code_of(ctx, user)["code"]
      assert %{"method" => "member_qr"} = desk(ctx, third) |> json_response(200)

      put_rules(ctx, %{member_code_mode: "rotating"})
      assert %{"code" => "invalid_member_code"} = desk(ctx, third) |> json_response(422)
      assert %{"mode" => "rotating"} = code_of(ctx, user)

      # Back to static: the old code stays dead, a new one is issued.
      put_rules(ctx, %{member_code_mode: "static"})
      assert %{"code" => "member_code_revoked"} = desk(ctx, third) |> json_response(422)
      refute code_of(ctx, user)["code"] == third
    end
  end

  # ------------------------------------------------------------------ realtime

  describe "desk channel" do
    defp socket_for(user, slug) do
      {:ok, token, _claims} =
        Guardian.encode_and_sign(user, %{"sv" => user.security_version || 1},
          token_type: "access"
        )

      Phoenix.ChannelTest.connect(UserSocket, %{"token" => token, "organization_slug" => slug})
    end

    test "staff see check-ins and visitors live, first names only; members cannot join", ctx do
      {:ok, socket} = socket_for(ctx.owner, ctx.organization.slug)
      topic = "check_in:#{ctx.organization.id}"

      assert {:ok, _reply, _socket} =
               Phoenix.ChannelTest.subscribe_and_join(socket, CheckInChannel, topic)

      user = member(ctx, @open_gym)
      scan_door(ctx, user) |> json_response(200)

      Phoenix.ChannelTest.assert_push(
        "checked_in",
        %{kind: "open_gym", method: "door_qr"} = event
      )

      refute Map.has_key?(event, :email)

      scan_door(ctx, user_fixture()) |> json_response(200)
      Phoenix.ChannelTest.assert_push("visitor_scanned", %{location_id: _})

      outsider = member(ctx)
      {:ok, member_socket} = socket_for(outsider, ctx.organization.slug)

      assert {:error, %{reason: "unauthorized"}} =
               Phoenix.ChannelTest.subscribe_and_join(member_socket, CheckInChannel, topic)
    end
  end
end
