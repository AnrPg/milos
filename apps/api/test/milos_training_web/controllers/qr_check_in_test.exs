defmodule MilosTrainingWeb.QrCheckInTest do
  @moduledoc """
  ADR-155 (P2-M7): the door display and its rotating code, the member's door
  scan (booking, choice, idempotency, undo, open gym, suggestions, visitor
  with trials), the desk scan of a personal QR (problems, auto, override),
  the owner's check-in rules and the live desk channel.
  """

  use MilosTrainingWeb.ConnCase, async: false

  import MilosTraining.TestFixtures
  require Phoenix.ChannelTest

  alias MilosTraining.Application.{PublishBoxPublicProfile, UpdateBoxPublicProfile}
  alias MilosTraining.{Facility, Finance, Organizations, Repo, Scheduling, Trials}
  alias MilosTraining.Infrastructure.Auth.Guardian
  alias MilosTrainingWeb.{CheckInChannel, UserSocket}

  @endpoint MilosTrainingWeb.Endpoint

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
