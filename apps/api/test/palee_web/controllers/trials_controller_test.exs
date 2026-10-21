defmodule Palee.Web.TrialsControllerTest do
  @moduledoc """
  ADR-144 (P2-M3, board 6): trials at a published box, from the ask to the
  membership, and talking to the box afterwards.
  """

  use PaleeWeb.ConnCase, async: false

  import Palee.TestFixtures

  alias Palee.{Notifications, Organizations, Repo, Scheduling}
  alias Palee.Application.{PublishBoxPublicProfile, TrialSteps, UpdateBoxPublicProfile}
  alias Palee.Scheduling.Booking
  alias Palee.Trials.TrialRequest

  setup %{conn: conn} do
    start_supervised!(
      {Oban, Keyword.put(Application.fetch_env!(:palee, Oban), :testing, :manual)}
    )

    {:ok, organization} =
      Organizations.create_organization(%{
        name: "Trial Gym #{System.unique_integer([:positive])}"
      })

    person = fn role ->
      user = user_fixture()

      if role do
        {:ok, _membership} =
          Organizations.add_membership(%{
            organization_id: organization.id,
            user_id: user.id,
            role: role,
            status: :active,
            joined_at: DateTime.utc_now()
          })
      end

      user
    end

    owner = person.(:owner)
    {:ok, owner_context} = Organizations.resolve_tenant_context(owner, organization.slug)

    {:ok, profile} =
      UpdateBoxPublicProfile.call(owner_context, %{
        "about" => "Δοκίμασε μας.",
        "disciplines" => ["crossfit"]
      })

    {:ok, _profile} =
      PublishBoxPublicProfile.publish(owner_context, %{"lock_version" => profile.lock_version})

    class_type = class_type_fixture(%{tenant_context: owner_context})
    workout = workout_fixture(owner, %{tenant_context: owner_context})

    slot = fn hours, attrs ->
      slot_fixture(
        workout,
        Map.merge(
          %{
            tenant_context: owner_context,
            class_type_id: class_type.id,
            scheduled_at:
              DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.add(hours, :hour)
          },
          attrs
        )
      )
    end

    %{
      organization: organization,
      slug: organization.slug,
      owner: owner,
      owner_context: owner_context,
      member: person.(:member),
      visitor: person.(nil),
      other: person.(nil),
      class_type: class_type,
      slot: slot,
      as: fn user -> put_bearer_token(conn, user) end,
      admin: "/api/org/#{organization.slug}/admin"
    }
  end

  defp send_json(conn, method, path, body) do
    conn
    |> put_req_header("content-type", "application/json")
    |> dispatch(@endpoint, method, path, Jason.encode!(body))
  end

  defp policy!(ctx, attrs) do
    ctx.as.(ctx.owner)
    |> send_json(:put, "#{ctx.admin}/trial-policy", Map.merge(%{enabled: true}, attrs))
    |> json_response(200)
  end

  defp ask(ctx, user, slot, extra \\ %{}) do
    ctx.as.(user)
    |> send_json(
      :post,
      "/api/boxes/#{ctx.slug}/trials",
      Map.merge(%{scheduled_class_id: slot.id}, extra)
    )
  end

  defp drain, do: Oban.drain_queue(queue: :notifications, with_safety: false)
  defp types(user), do: Notifications.list_for_user(user.id) |> Enum.map(&to_string(&1.type))

  describe "the offer on the box page" do
    test "is off until the owner opens trials, then shows seats per class", ctx do
      open = ctx.slot.(24, %{capacity: 10})
      full = ctx.slot.(30, %{capacity: 1})

      {:ok, _booking} =
        Scheduling.submit_auto_approved_booking(ctx.owner_context, ctx.member.id, full.id)

      schedule = fn user ->
        ctx.as.(user) |> get("/api/boxes/#{ctx.slug}/schedule") |> json_response(200)
      end

      assert %{"trial_offer" => nil} = schedule.(ctx.visitor)

      policy!(ctx, %{seats_per_class: 2, bring_note: "Νερό και πετσέτα"})

      assert %{"trial_offer" => offer, "slots" => slots} = schedule.(ctx.visitor)

      assert %{"enabled" => true, "approval" => "auto", "bring_note" => "Νερό και πετσέτα"} =
               offer

      assert offer["blocked_reason"] == nil
      seats = Map.new(slots, &{&1["id"], &1["trial_seats"]})
      assert seats[open.id] == 2
      assert seats[full.id] == 0

      # Members see no offer.
      assert %{"trial_offer" => nil} = schedule.(ctx.member)
    end

    test "only the class types the owner picked take trials", ctx do
      other_type = class_type_fixture(%{tenant_context: ctx.owner_context})
      picked = ctx.slot.(24, %{})
      skipped = ctx.slot.(26, %{class_type_id: other_type.id})
      policy!(ctx, %{class_type_ids: [ctx.class_type.id]})

      seats =
        ctx.as.(ctx.visitor)
        |> get("/api/boxes/#{ctx.slug}/schedule")
        |> json_response(200)
        |> Map.fetch!("slots")
        |> Map.new(&{&1["id"], &1["trial_seats"]})

      assert seats[picked.id] == 2
      assert seats[skipped.id] == nil

      assert %{"code" => "class_not_open_to_trials"} =
               ask(ctx, ctx.visitor, skipped) |> json_response(422)
    end
  end

  describe "asking for a trial" do
    test "books at once on auto approval, idempotently, as a trial seat off any package", ctx do
      slot = ctx.slot.(24, %{})
      assert %{"code" => "trials_disabled"} = ask(ctx, ctx.visitor, slot) |> json_response(422)

      policy!(ctx, %{})
      operation = Ecto.UUID.generate()

      assert %{"trial" => trial} =
               ask(ctx, ctx.visitor, slot, %{
                 client_operation_id: operation,
                 note: "Πρώτη φορά CrossFit",
                 phone: "+30 690 000 0000"
               })
               |> json_response(201)

      assert %{"status" => "booked", "booking_id" => booking_id, "follow_up" => false} = trial
      assert trial["box"]["slug"] == ctx.slug
      assert trial["class"]["id"] == slot.id

      booking = Repo.get!(Booking, booking_id)

      assert {booking.kind, booking.entitlement_allowance, booking.status} ==
               {"trial", "none", :approved}

      # A retry returns the same trial.
      assert %{"trial" => %{"id" => same}} =
               ask(ctx, ctx.visitor, slot, %{client_operation_id: operation})
               |> json_response(201)

      assert same == trial["id"]

      # One open trial per box.
      assert %{"code" => "trial_already_open"} =
               ask(ctx, ctx.visitor, ctx.slot.(48, %{})) |> json_response(409)

      drain()
      assert "trial_booked" in types(ctx.owner)

      assert %{"trials" => [%{"id" => ^same}]} =
               ctx.as.(ctx.visitor) |> get("/api/me/trials") |> json_response(200)
    end

    test "members, used-up and seat limits are refused", ctx do
      slot = ctx.slot.(24, %{})
      policy!(ctx, %{seats_per_class: 1})

      assert %{"code" => "already_member"} = ask(ctx, ctx.member, slot) |> json_response(422)
      assert ask(ctx, ctx.visitor, slot) |> json_response(201)
      assert %{"code" => "no_trial_seats"} = ask(ctx, ctx.other, slot) |> json_response(409)
    end

    test "the weekly limit counts the whole box", ctx do
      first = ctx.slot.(24, %{})
      second = ctx.slot.(25, %{})
      policy!(ctx, %{weekly_limit: 1})

      # Same week unless the two classes straddle Sunday midnight in UTC.
      zone = Organizations.organization_timezone(ctx.organization.id)
      {_from, to} = Palee.Trials.week_of(first.scheduled_at, zone)

      assert ask(ctx, ctx.visitor, first) |> json_response(201)

      if DateTime.compare(second.scheduled_at, to) == :lt do
        assert %{"code" => "weekly_trial_limit_reached"} =
                 ask(ctx, ctx.other, second) |> json_response(409)
      end
    end

    test "a cancelled trial frees the seat and doesn't use up the trial", ctx do
      slot = ctx.slot.(24, %{})
      policy!(ctx, %{seats_per_class: 1})

      %{"trial" => %{"id" => id, "booking_id" => booking_id}} =
        ask(ctx, ctx.visitor, slot) |> json_response(201)

      assert %{"trial" => %{"status" => "cancelled"}} =
               ctx.as.(ctx.visitor) |> post("/api/me/trials/#{id}/cancel") |> json_response(200)

      refute Repo.get(Booking, booking_id)
      drain()
      assert "trial_cancelled" in types(ctx.owner)

      # The seat is free for someone else, and the visitor may ask again.
      assert ask(ctx, ctx.other, slot) |> json_response(201)
      assert ask(ctx, ctx.visitor, ctx.slot.(48, %{})) |> json_response(201)

      # Another person's trial is not theirs to read or cancel.
      assert ctx.as.(ctx.other) |> post("/api/me/trials/#{id}/cancel") |> json_response(404)
    end
  end

  describe "staff" do
    test "accept and decline asks on manual approval", ctx do
      slot = ctx.slot.(24, %{})
      policy!(ctx, %{approval: "manual"})

      %{"trial" => %{"id" => asked, "status" => "requested", "booking_id" => nil}} =
        ask(ctx, ctx.visitor, slot) |> json_response(201)

      %{"trial" => %{"id" => other}} = ask(ctx, ctx.other, slot) |> json_response(201)

      assert %{"counts" => %{"requests" => 2}, "trials" => [_, _]} =
               ctx.as.(ctx.owner)
               |> get("#{ctx.admin}/trials?stage=requests")
               |> json_response(200)

      assert %{"trial" => %{"status" => "booked", "booking_id" => booking_id}} =
               ctx.as.(ctx.owner)
               |> post("#{ctx.admin}/trials/#{asked}/accept")
               |> json_response(200)

      assert Repo.get!(Booking, booking_id).kind == "trial"

      assert %{"trial" => %{"status" => "declined", "decline_reason" => "Γεμάτο"}} =
               ctx.as.(ctx.owner)
               |> send_json(:post, "#{ctx.admin}/trials/#{other}/decline", %{reason: "Γεμάτο"})
               |> json_response(200)

      assert ctx.as.(ctx.owner)
             |> post("#{ctx.admin}/trials/#{asked}/accept")
             |> json_response(409)

      drain()
      assert "trial_requested" in types(ctx.owner)
      assert "trial_accepted" in types(ctx.visitor)
      assert "trial_declined" in types(ctx.other)

      # Members and visitors can't reach the queue.
      assert ctx.as.(ctx.member) |> get("#{ctx.admin}/trials") |> response(403)
    end

    test "an unanswered ask expires at class time", ctx do
      slot = ctx.slot.(24, %{})
      policy!(ctx, %{approval: "manual"})
      %{"trial" => %{"id" => id}} = ask(ctx, ctx.visitor, slot) |> json_response(201)

      assert :ok = TrialSteps.run(ctx.organization.id, id, :expire)
      assert Repo.get!(TrialRequest, id).status == "expired"
    end

    test "attendance on the roster marks the trial; joining converts it", ctx do
      slot = ctx.slot.(1, %{})
      policy!(ctx, %{})
      %{"trial" => %{"id" => id}} = ask(ctx, ctx.visitor, slot) |> json_response(201)

      assert :ok = TrialSteps.run(ctx.organization.id, id, :reminder)
      drain()
      assert "trial_reminder" in types(ctx.visitor)

      assert %{"trial" => %{"status" => "no_show"}} =
               ctx.as.(ctx.owner)
               |> send_json(:post, "#{ctx.admin}/trials/#{id}/attendance", %{status: "no_show"})
               |> json_response(200)

      assert %{"trial" => %{"status" => "attended"}} =
               ctx.as.(ctx.owner)
               |> send_json(:post, "#{ctx.admin}/trials/#{id}/attendance", %{status: "attended"})
               |> json_response(200)

      assert %{"counts" => %{"visited" => 1}} =
               ctx.as.(ctx.owner)
               |> get("#{ctx.admin}/trials?stage=visited")
               |> json_response(200)

      assert %{"trials" => [%{"follow_up" => true}]} =
               ctx.as.(ctx.visitor) |> get("/api/me/trials") |> json_response(200)

      assert :ok = TrialSteps.run(ctx.organization.id, id, :follow_up)
      drain()
      assert "trial_follow_up" in types(ctx.visitor)

      {:ok, _membership} =
        Organizations.add_membership(%{
          organization_id: ctx.organization.id,
          user_id: ctx.visitor.id,
          role: :member,
          status: :active,
          joined_at: DateTime.utc_now()
        })

      assert Repo.get!(TrialRequest, id).status == "converted"

      assert %{"counts" => %{"joined" => 1}, "stats" => %{"converted" => 1}} =
               ctx.as.(ctx.owner) |> get("#{ctx.admin}/trials?stage=joined") |> json_response(200)
    end

    test "deleting the class ends the asks waiting in it", ctx do
      slot = ctx.slot.(24, %{})
      policy!(ctx, %{approval: "manual"})
      %{"trial" => %{"id" => id}} = ask(ctx, ctx.visitor, slot) |> json_response(201)

      assert ctx.as.(ctx.owner)
             |> delete("#{ctx.admin}/schedule/slots/#{slot.id}")
             |> response(204)

      trial = Repo.get!(TrialRequest, id)
      assert trial.status == "cancelled"
      assert trial.class_name == slot.name
    end

    test "the package for new members must be the box's own", ctx do
      assert %{"code" => "package_not_found"} =
               ctx.as.(ctx.owner)
               |> send_json(:put, "#{ctx.admin}/trial-policy", %{
                 conversion_package_id: Ecto.UUID.generate()
               })
               |> json_response(422)

      assert %{"policy" => %{"enabled" => false}, "this_week" => 0} =
               ctx.as.(ctx.owner) |> get("#{ctx.admin}/trial-policy") |> json_response(200)
    end
  end

  describe "«Θέλω να γραφτώ»" do
    test "opens a conversation with the box that staff answer", ctx do
      slot = ctx.slot.(1, %{})
      policy!(ctx, %{})

      # No conversation without a trial or a membership.
      assert ctx.as.(ctx.other) |> post("/api/boxes/#{ctx.slug}/conversation") |> response(403)

      %{"trial" => %{"id" => id}} = ask(ctx, ctx.visitor, slot) |> json_response(201)

      ctx.as.(ctx.owner)
      |> send_json(:post, "#{ctx.admin}/trials/#{id}/attendance", %{status: "attended"})
      |> json_response(200)

      assert %{"trial" => %{"follow_up" => false}, "conversation" => %{"thread_id" => thread_id}} =
               ctx.as.(ctx.visitor)
               |> send_json(:post, "/api/me/trials/#{id}/follow-up", %{action: "join"})
               |> json_response(200)

      assert %{"message" => %{"body" => "Θέλω να γραφτώ!"}} =
               ctx.as.(ctx.visitor)
               |> send_json(:post, "/api/boxes/#{ctx.slug}/conversation/messages", %{
                 body: "Θέλω να γραφτώ!"
               })
               |> json_response(201)

      assert %{"conversation" => %{"thread_id" => ^thread_id, "messages" => [_]}} =
               ctx.as.(ctx.visitor)
               |> get("/api/boxes/#{ctx.slug}/conversation")
               |> json_response(200)

      assert %{"conversations" => [%{"thread_id" => ^thread_id, "box" => %{"slug" => slug}}]} =
               ctx.as.(ctx.visitor) |> get("/api/me/box-conversations") |> json_response(200)

      assert slug == ctx.slug

      # Strangers can't read it.
      assert ctx.as.(ctx.other) |> get("/api/boxes/#{ctx.slug}/conversation") |> response(404)
    end
  end
end
