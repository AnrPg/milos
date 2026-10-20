defmodule MilosTrainingWeb.CommunityEventsControllerTest do
  @moduledoc """
  ADR-153 (P2-M5, board 8): club events from the member app and from
  «Κοινότητα»: places and the waitlist, guest passes, payments, check-in, the
  trial offer, weekly series, reminders and the feed card.
  """

  use MilosTrainingWeb.ConnCase, async: false

  import Ecto.Query
  import MilosTraining.TestFixtures

  alias MilosTraining.Application.{
    EventReminders,
    PublishBoxPublicProfile,
    UpdateBoxPublicProfile
  }

  alias MilosTraining.Community.{Event, EventAttendee, Post}
  alias MilosTraining.{Community, Notifications, Organizations, Repo}
  alias MilosTraining.Trials.TrialRequest

  setup %{conn: conn} do
    start_supervised!(
      {Oban, Keyword.put(Application.fetch_env!(:milos_training, Oban), :testing, :manual)}
    )

    {:ok, organization} =
      Organizations.create_organization(%{
        name: "Event Gym #{System.unique_integer([:positive])}"
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
        "about" => "Έλα να γνωριστούμε.",
        "disciplines" => ["crossfit"]
      })

    {:ok, _profile} =
      PublishBoxPublicProfile.publish(owner_context, %{"lock_version" => profile.lock_version})

    as = fn user -> put_bearer_token(conn, user) end
    member = person.(:member)

    club_id =
      as.(member)
      |> get("/api/me/clubs")
      |> json_response(200)
      |> Map.fetch!("clubs")
      |> Enum.find(&(&1["kind"] == "gym"))
      |> Map.fetch!("id")

    %{
      organization: organization,
      slug: organization.slug,
      owner: owner,
      coach: person.(:coach),
      member: member,
      other: person.(:member),
      visitor: person.(nil),
      stranger: person.(nil),
      club_id: club_id,
      as: as,
      staff: "/api/org/#{organization.slug}/admin/community/events"
    }
  end

  defp send_json(conn, method, path, body) do
    conn
    |> put_req_header("content-type", "application/json")
    |> dispatch(@endpoint, method, path, Jason.encode!(body))
  end

  defp at(minutes),
    do:
      DateTime.utc_now()
      |> DateTime.truncate(:second)
      |> DateTime.add(minutes, :minute)
      |> DateTime.to_iso8601()

  defp new_event(ctx, attrs \\ %{}) do
    body =
      Map.merge(
        %{
          club_id: ctx.club_id,
          title: "Τρέξιμο στον Φιλοπάππου",
          starts_at: at(2 * 24 * 60),
          ends_at: at(2 * 24 * 60 + 60),
          place_name: "Λόφος Φιλοπάππου"
        },
        attrs
      )

    ctx.as.(ctx.coach)
    |> send_json(:post, ctx.staff, body)
    |> json_response(201)
    |> Map.fetch!("event")
  end

  defp rsvp(ctx, user, event, going, extra \\ %{}) do
    ctx.as.(user)
    |> send_json(:put, "/api/me/events/#{event["id"]}/rsvp", Map.merge(%{going: going}, extra))
  end

  defp staff_show(ctx, event),
    do: ctx.as.(ctx.coach) |> get("#{ctx.staff}/#{event["id"]}") |> json_response(200)

  defp event_json(conn), do: conn |> json_response(200) |> Map.fetch!("event")

  defp drain, do: Oban.drain_queue(queue: :notifications, with_safety: false)

  defp types(user), do: Notifications.list_for_user(user.id) |> Enum.map(&to_string(&1.type))

  defp end_event(event) do
    Repo.update_all(
      from(e in Event, where: e.id == ^event["id"]),
      set: [
        starts_at: DateTime.add(DateTime.utc_now(), -3, :hour),
        ends_at: DateTime.add(DateTime.utc_now(), -2, :hour)
      ]
    )
  end

  describe "publishing" do
    test "an event posts its card in the club feed and shows in the club's lists", ctx do
      event = new_event(ctx, %{capacity: 10, description: "Χαλαρό τρέξιμο, 8 χλμ."})

      assert %{"post_id" => post_id, "can_manage" => true, "spots_left" => 10} = event
      assert %Post{attachment_type: "event"} = Repo.get(Post, post_id)

      assert %{"posts" => posts} =
               ctx.as.(ctx.member) |> get("/api/me/feed") |> json_response(200)

      assert %{"event" => %{"id" => event_id}} = Enum.find(posts, &(&1["id"] == post_id))
      assert event_id == event["id"]

      assert %{"events" => [%{"id" => ^event_id, "can_manage" => false, "can_rsvp" => true}]} =
               ctx.as.(ctx.member)
               |> get("/api/me/community/clubs/#{ctx.club_id}/events")
               |> json_response(200)

      assert %{"events" => [%{"id" => ^event_id}]} =
               ctx.as.(ctx.member) |> get("/api/me/community/events") |> json_response(200)

      # Members-only: invisible to someone outside the club, and not on the box page.
      assert ctx.as.(ctx.visitor) |> get("/api/me/events/#{event_id}") |> json_response(404)

      assert %{"code" => "not_found"} =
               rsvp(ctx, ctx.visitor, event, true) |> json_response(404)

      assert %{"events" => []} =
               ctx.as.(ctx.visitor) |> get("/api/boxes/#{ctx.slug}/events") |> json_response(200)
    end

    test "staff and coaches run events from the club page; members can't", ctx do
      body = %{
        title: "Πικνίκ",
        starts_at: at(3 * 24 * 60),
        ends_at: at(3 * 24 * 60 + 120),
        place_name: "Πεδίον του Άρεως"
      }

      path = "/api/me/community/clubs/#{ctx.club_id}/events"

      assert %{"event" => %{"id" => id, "can_manage" => true}, "occurrences" => 1} =
               ctx.as.(ctx.coach) |> send_json(:post, path, body) |> json_response(201)

      assert ctx.as.(ctx.member) |> send_json(:post, path, body) |> json_response(403)

      assert %{"event" => %{"title" => "Πικνίκ στο πάρκο"}} =
               ctx.as.(ctx.owner)
               |> send_json(:patch, "/api/me/events/#{id}", %{title: "Πικνίκ στο πάρκο"})
               |> json_response(200)

      assert ctx.as.(ctx.member)
             |> send_json(:post, "/api/me/events/#{id}/cancel", %{})
             |> json_response(403)
    end

    test "an event needs somewhere to go, and only one of a location or a place", ctx do
      assert %{"errors" => %{"location_id" => _}} =
               ctx.as.(ctx.coach)
               |> send_json(:post, ctx.staff, %{
                 club_id: ctx.club_id,
                 title: "Κάπου",
                 starts_at: at(60 * 24),
                 ends_at: at(60 * 25)
               })
               |> json_response(422)
    end
  end

  describe "places" do
    test "the waitlist moves up when a place frees, and its new holder hears", ctx do
      event = new_event(ctx, %{capacity: 1})

      assert %{"my" => %{"status" => "going"}, "spots_left" => 0} =
               rsvp(ctx, ctx.member, event, true) |> event_json()

      # Saying it twice changes nothing.
      assert %{"my" => %{"status" => "going"}, "going_count" => 1} =
               rsvp(ctx, ctx.member, event, true) |> event_json()

      assert %{"my" => %{"status" => "waitlisted"}, "waitlist_count" => 1} =
               rsvp(ctx, ctx.other, event, true) |> event_json()

      assert %{"my" => %{"status" => "cancelled", "late_cancel" => false}} =
               rsvp(ctx, ctx.member, event, false) |> event_json()

      assert %{"my" => %{"status" => "going"}} =
               ctx.as.(ctx.other) |> get("/api/me/events/#{event["id"]}") |> event_json()

      drain()
      assert "community_event_waitlist_promoted" in types(ctx.other)

      assert %{"events" => [%{"id" => id}]} =
               ctx.as.(ctx.other) |> get("/api/me/events") |> json_response(200)

      assert id == event["id"]
    end

    test "giving up a place within two hours of the start is a late cancel", ctx do
      event = new_event(ctx, %{starts_at: at(90), ends_at: at(150)})
      rsvp(ctx, ctx.member, event, true) |> event_json()

      assert %{"my" => %{"status" => "cancelled", "late_cancel" => true}} =
               rsvp(ctx, ctx.member, event, false) |> event_json()

      assert %{"event" => %{"stats" => %{"late_cancels" => 1, "going" => 0}}} =
               staff_show(ctx, event)

      # Staff see «Ακύρωσε αργά» with when, and how often this person did it lately.
      later = new_event(ctx, %{starts_at: at(100), ends_at: at(160)})
      rsvp(ctx, ctx.member, later, true) |> event_json()
      rsvp(ctx, ctx.member, later, false) |> event_json()

      assert %{"event" => %{"attendees" => %{"cancelled" => [row]}}} = staff_show(ctx, later)

      assert %{"late_cancel" => true, "cancelled_at" => cancelled_at, "late_cancels_90d" => 2} =
               row

      assert cancelled_at
    end

    test "staff free a place and the first on the waitlist gets it, without a late cancel", ctx do
      event = new_event(ctx, %{capacity: 1, starts_at: at(60), ends_at: at(120)})
      rsvp(ctx, ctx.member, event, true) |> event_json()
      rsvp(ctx, ctx.other, event, true) |> event_json()

      assert %{"event" => %{"attendees" => %{"going" => [going], "cancelled" => [freed]}}} =
               ctx.as.(ctx.coach)
               |> delete("#{ctx.staff}/#{event["id"]}/attendees/#{ctx.member.id}")
               |> json_response(200)

      assert going["person"]["id"] == ctx.other.id
      assert %{"late_cancel" => false, "removed_by" => %{"id" => coach_id}} = freed
      assert coach_id == ctx.coach.id
    end

    test "places hold when many answer at once", ctx do
      event = new_event(ctx, %{capacity: 3})
      gym = %{organization_id: ctx.organization.id, user_id: ctx.coach.id}

      people =
        for _ <- 1..8 do
          user = user_fixture()

          {:ok, _} =
            Organizations.add_membership(%{
              organization_id: ctx.organization.id,
              user_id: user.id,
              role: :member,
              status: :active,
              joined_at: DateTime.utc_now()
            })

          user
        end

      people
      |> Enum.map(fn user ->
        Task.async(fn ->
          Community.rsvp_event(
            gym,
            event["id"],
            user.id,
            %{club_member?: true},
            DateTime.utc_now()
          )
        end)
      end)
      |> Enum.each(&assert({:ok, _} = Task.await(&1, 15_000)))

      statuses =
        Repo.all(from(a in EventAttendee, where: a.event_id == ^event["id"], select: a.status))

      assert Enum.frequencies(statuses) == %{"going" => 3, "waitlisted" => 5}
    end
  end

  describe "who can come" do
    test "anyone signed in on an open event, which shows on the box page; names stay in the club",
         ctx do
      event = new_event(ctx, %{open_to_non_members: true, capacity: 5})
      rsvp(ctx, ctx.member, event, true) |> event_json()

      assert %{"events" => [%{"id" => id}]} =
               ctx.as.(ctx.visitor) |> get("/api/boxes/#{ctx.slug}/events") |> json_response(200)

      assert id == event["id"]

      assert %{
               "my" => %{"status" => "going", "source" => "open"},
               "goers" => nil,
               "going_count" => 2
             } =
               rsvp(ctx, ctx.visitor, event, true) |> event_json()

      assert %{"goers" => goers} =
               ctx.as.(ctx.other) |> get("/api/me/events/#{event["id"]}") |> event_json()

      assert length(goers) == 2
    end

    test "a guest pass lets a friend come, as many as the member may bring", ctx do
      event = new_event(ctx, %{guest_pass_allowed: true, guests_per_member: 1})

      # Only someone going gets a pass.
      assert %{"code" => "inviter_not_going"} =
               ctx.as.(ctx.member)
               |> post("/api/me/events/#{event["id"]}/invites")
               |> json_response(409)

      rsvp(ctx, ctx.member, event, true) |> event_json()

      assert %{"token" => token, "guests_left" => 1, "path" => path} =
               ctx.as.(ctx.member)
               |> post("/api/me/events/#{event["id"]}/invites")
               |> json_response(201)

      assert path =~ "/events/#{event["id"]}?invite="

      assert %{"invitation" => %{"usable" => true, "inviter" => %{"id" => inviter_id}}} =
               ctx.as.(ctx.visitor)
               |> get("/api/me/events/#{event["id"]}?invite=#{token}")
               |> event_json()

      assert inviter_id == ctx.member.id

      assert %{
               "my" => %{"status" => "going", "source" => "guest", "invited_by_id" => ^inviter_id}
             } =
               rsvp(ctx, ctx.visitor, event, true, %{invite_token: token}) |> event_json()

      assert %{"code" => "guest_limit_reached"} =
               rsvp(ctx, ctx.stranger, event, true, %{invite_token: token}) |> json_response(409)

      # A forged or foreign token is no invitation.
      assert rsvp(ctx, ctx.stranger, event, true, %{invite_token: token <> "x"})
             |> json_response(404)

      drain()
      assert "community_event_guest_joined" in types(ctx.member)
    end

    test "events that take no guests give no passes", ctx do
      event = new_event(ctx)
      rsvp(ctx, ctx.member, event, true) |> event_json()

      assert %{"code" => "guests_not_allowed"} =
               ctx.as.(ctx.member)
               |> post("/api/me/events/#{event["id"]}/invites")
               |> json_response(403)
    end
  end

  describe "running the event" do
    test "check-in, «Πλήρωσε», a message to all and the numbers", ctx do
      event = new_event(ctx, %{open_to_non_members: true, price_cents: 1500})
      rsvp(ctx, ctx.member, event, true) |> event_json()
      rsvp(ctx, ctx.visitor, event, true) |> event_json()
      base = "#{ctx.staff}/#{event["id"]}/attendees"

      assert %{"event" => %{"attendees" => %{"going" => going}}} =
               ctx.as.(ctx.coach)
               |> send_json(:put, "#{base}/#{ctx.visitor.id}/check-in", %{checked_in: true})
               |> json_response(200)

      assert %{"checked_in_at" => checked_in, "member" => false} =
               Enum.find(going, &(&1["person"]["id"] == ctx.visitor.id))

      assert checked_in

      assert %{"event" => %{"attendees" => %{"going" => going}, "stats" => stats}} =
               ctx.as.(ctx.coach)
               |> send_json(:put, "#{base}/#{ctx.visitor.id}/paid", %{payment_method: "cash"})
               |> json_response(200)

      assert %{"paid_at" => paid_at, "amount_cents" => 1500, "payment_method" => "cash"} =
               Enum.find(going, &(&1["person"]["id"] == ctx.visitor.id))

      assert paid_at
      assert %{"going" => 2, "came" => 1, "paid" => 1} = stats

      assert %{"code" => "already_paid"} =
               ctx.as.(ctx.coach)
               |> send_json(:put, "#{base}/#{ctx.visitor.id}/paid", %{payment_method: "cash"})
               |> json_response(409)

      # Members don't run events.
      assert ctx.as.(ctx.member)
             |> send_json(:put, "#{base}/#{ctx.visitor.id}/check-in", %{checked_in: true})
             |> json_response(403)

      assert %{"sent" => 2} =
               ctx.as.(ctx.coach)
               |> send_json(:post, "#{ctx.staff}/#{event["id"]}/message", %{body: "Φέρτε νερό"})
               |> json_response(200)

      drain()
      assert "community_event_message" in types(ctx.visitor)

      assert %{"events" => [%{"id" => id, "stats" => %{"paid" => 1}}]} =
               ctx.as.(ctx.coach) |> get(ctx.staff) |> json_response(200)

      assert id == event["id"]
    end

    test "free events take no payments", ctx do
      event = new_event(ctx)
      rsvp(ctx, ctx.member, event, true) |> event_json()

      assert %{"code" => "event_is_free"} =
               ctx.as.(ctx.coach)
               |> send_json(
                 :put,
                 "#{ctx.staff}/#{event["id"]}/attendees/#{ctx.member.id}/paid",
                 %{payment_method: "cash"}
               )
               |> json_response(422)
    end

    test "the trial offer goes once, after the event, to non-members who came", ctx do
      event = new_event(ctx, %{open_to_non_members: true})
      base = "#{ctx.staff}/#{event["id"]}"

      for user <- [ctx.member, ctx.visitor, ctx.stranger],
          do: rsvp(ctx, user, event, true) |> event_json()

      # The member and the visitor came; the stranger didn't.
      for user <- [ctx.member, ctx.visitor] do
        ctx.as.(ctx.coach)
        |> send_json(:put, "#{base}/attendees/#{user.id}/check-in", %{checked_in: true})
        |> json_response(200)
      end

      offer = fn -> ctx.as.(ctx.coach) |> post("#{base}/trial-offer") end

      assert %{"code" => "event_not_over"} = offer.() |> json_response(409)

      end_event(event)
      assert %{"code" => "trials_disabled"} = offer.() |> json_response(422)

      ctx.as.(ctx.owner)
      |> send_json(:put, "/api/org/#{ctx.slug}/admin/trial-policy", %{enabled: true})
      |> json_response(200)

      assert %{"event" => %{"trial_offer" => %{"can_send" => true, "recipients" => 1}}} =
               staff_show(ctx, event)

      assert %{"sent" => 1} = offer.() |> json_response(200)
      assert %{"code" => "trial_offer_already_sent"} = offer.() |> json_response(409)

      drain()
      assert "community_event_trial_offer" in types(ctx.visitor)
      refute "community_event_trial_offer" in types(ctx.member)
      refute "community_event_trial_offer" in types(ctx.stranger)

      [notification] =
        ctx.visitor.id
        |> Notifications.list_for_user()
        |> Enum.filter(&(to_string(&1.type) == "community_event_trial_offer"))

      assert notification.payload["url"] =~ "referral_event_id=#{event["id"]}"

      assert %{"event" => %{"trial_offer" => %{"sent_at" => sent_at, "can_send" => false}}} =
               staff_show(ctx, event)

      assert sent_at
    end

    test "a trial request names the event that brought the person", ctx do
      event = new_event(ctx, %{open_to_non_members: true})
      owner_context = elem(Organizations.resolve_tenant_context(ctx.owner, ctx.slug), 1)
      class_type = class_type_fixture(%{tenant_context: owner_context})
      workout = workout_fixture(ctx.owner, %{tenant_context: owner_context})

      slot =
        slot_fixture(workout, %{
          tenant_context: owner_context,
          class_type_id: class_type.id,
          scheduled_at: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.add(1, :day)
        })

      ctx.as.(ctx.owner)
      |> send_json(:put, "/api/org/#{ctx.slug}/admin/trial-policy", %{enabled: true})
      |> json_response(200)

      ask = fn user, event_id ->
        ctx.as.(user)
        |> send_json(:post, "/api/boxes/#{ctx.slug}/trials", %{
          scheduled_class_id: slot.id,
          referral_event_id: event_id
        })
      end

      assert %{"code" => "event_not_found"} =
               ask.(ctx.stranger, Ecto.UUID.generate()) |> json_response(404)

      assert %{"trial" => %{"id" => trial_id}} =
               ask.(ctx.visitor, event["id"]) |> json_response(201)

      assert %TrialRequest{referral_event_id: referral_event_id, source: "event"} =
               Repo.get(TrialRequest, trial_id)

      assert referral_event_id == event["id"]

      assert %{"event" => %{"stats" => %{"trial_requests" => 1}}} = staff_show(ctx, event)
    end
  end

  describe "member group events" do
    defp group!(ctx) do
      community = "/api/org/#{ctx.slug}/community"

      %{"group" => %{"id" => group_id}} =
        ctx.as.(ctx.member)
        |> send_json(:post, "#{community}/groups", %{name: "Πρωινοί δρομείς", join_policy: "open"})
        |> json_response(201)

      ctx.as.(ctx.coach)
      |> send_json(:put, "/api/org/#{ctx.slug}/admin/community/groups/#{group_id}/decision", %{
        decision: "approve"
      })
      |> json_response(200)

      ctx.as.(ctx.other)
      |> post("#{community}/groups/#{group_id}/membership")
      |> json_response(200)

      group_id
    end

    defp club_member!(ctx) do
      user = user_fixture()

      {:ok, _} =
        Organizations.add_membership(%{
          organization_id: ctx.organization.id,
          user_id: user.id,
          role: :member,
          status: :active,
          joined_at: DateTime.utc_now()
        })

      user
    end

    test "a group's admin runs free, members-only events that only the group sees", ctx do
      group_id = group!(ctx)
      outside = club_member!(ctx)
      path = "/api/me/community/clubs/#{ctx.club_id}/events"

      body = %{
        channel_id: group_id,
        title: "Τρέξιμο της ομάδας",
        starts_at: at(2 * 24 * 60),
        ends_at: at(2 * 24 * 60 + 60),
        place_name: "Λόφος Φιλοπάππου",
        price_cents: 2000,
        open_to_non_members: true,
        guest_pass_allowed: true
      }

      assert %{"event" => event} =
               ctx.as.(ctx.member) |> send_json(:post, path, body) |> json_response(201)

      assert %{
               "channel_id" => ^group_id,
               "group" => %{"id" => ^group_id, "name" => "Πρωινοί δρομείς"},
               "price_cents" => 0,
               "open_to_non_members" => false,
               "guest_pass_allowed" => false,
               "can_manage" => true
             } = event

      # Its card goes in the group, not the announcements.
      assert %Post{channel_id: ^group_id, attachment_type: "event"} =
               Repo.get(Post, event["post_id"])

      # The group's members see it and come.
      assert %{"events" => [%{"id" => id, "can_rsvp" => true, "can_manage" => false}]} =
               ctx.as.(ctx.other) |> get(path) |> json_response(200)

      assert id == event["id"]

      assert %{"my" => %{"status" => "going", "source" => "member"}, "goers" => [_]} =
               rsvp(ctx, ctx.other, event, true) |> event_json()

      # A club member outside the group, and someone outside the club, don't.
      assert %{"events" => []} = ctx.as.(outside) |> get(path) |> json_response(200)

      assert %{"events" => []} =
               ctx.as.(outside) |> get("/api/me/community/events") |> json_response(200)

      assert ctx.as.(outside) |> get("/api/me/events/#{id}") |> json_response(404)
      assert rsvp(ctx, outside, event, true) |> json_response(404)
      assert rsvp(ctx, ctx.visitor, event, true) |> json_response(404)

      # The admin edits it; it stays free and closed.
      assert %{"event" => %{"title" => "Τρέξιμο της ομάδας (8 χλμ.)", "price_cents" => 0}} =
               ctx.as.(ctx.member)
               |> send_json(:patch, "/api/me/events/#{id}", %{
                 title: "Τρέξιμο της ομάδας (8 χλμ.)",
                 price_cents: 500
               })
               |> json_response(200)

      # A plain member of the group runs nothing; the admin runs no club events.
      assert ctx.as.(ctx.other)
             |> send_json(:patch, "/api/me/events/#{id}", %{title: "Δικό μου"})
             |> json_response(403)

      assert ctx.as.(ctx.other) |> send_json(:post, path, body) |> json_response(403)

      assert ctx.as.(ctx.member)
             |> send_json(:post, path, Map.delete(body, :channel_id))
             |> json_response(403)

      # Staff with manage_events see and manage it like any other event.
      assert %{"events" => events} = ctx.as.(ctx.coach) |> get(ctx.staff) |> json_response(200)
      assert Enum.any?(events, &(&1["id"] == id and &1["channel_id"] == group_id))

      assert %{"event" => %{"cancelled" => true}} =
               ctx.as.(ctx.coach)
               |> send_json(:post, "#{ctx.staff}/#{id}/cancel", %{reason: "Βροχή"})
               |> json_response(200)

      drain()
      assert "community_event_cancelled" in types(ctx.other)
    end

    test "events go only in an active group of the club", ctx do
      %{"group" => %{"id" => pending_id}} =
        ctx.as.(ctx.other)
        |> send_json(:post, "/api/org/#{ctx.slug}/community/groups", %{
          name: "Ακόμα σε αναμονή",
          join_policy: "open"
        })
        |> json_response(201)

      assert ctx.as.(ctx.other)
             |> send_json(:post, "/api/me/community/clubs/#{ctx.club_id}/events", %{
               channel_id: pending_id,
               title: "Πρώτο τρέξιμο",
               starts_at: at(24 * 60),
               ends_at: at(25 * 60),
               place_name: "Πάρκο"
             })
             |> json_response(404)
    end
  end

  describe "changes" do
    test "a weekly event edits and cancels «this and following»", ctx do
      first_start = DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.add(2, :day)

      created =
        ctx.as.(ctx.coach)
        |> send_json(:post, ctx.staff, %{
          club_id: ctx.club_id,
          title: "Κυριακάτικο τρέξιμο",
          starts_at: DateTime.to_iso8601(first_start),
          ends_at: first_start |> DateTime.add(1, :hour) |> DateTime.to_iso8601(),
          place_name: "Λόφος Φιλοπάππου",
          repeat_until:
            first_start |> DateTime.add(21, :day) |> DateTime.to_date() |> Date.to_iso8601()
        })
        |> json_response(201)

      assert %{"occurrences" => 4, "event" => %{"series_id" => series_id}} = created
      assert series_id

      series = fn ->
        ctx.as.(ctx.coach)
        |> get(ctx.staff)
        |> json_response(200)
        |> Map.fetch!("events")
        |> Enum.filter(&(&1["series_id"] == series_id))
        |> Enum.sort_by(& &1["starts_at"])
      end

      [first, second, _third, _fourth] = before = series.()
      rsvp(ctx, ctx.member, second, true) |> event_json()

      {:ok, second_start, _} = DateTime.from_iso8601(second["starts_at"])
      moved = DateTime.add(second_start, 30, :minute)

      ctx.as.(ctx.coach)
      |> send_json(:patch, "#{ctx.staff}/#{second["id"]}", %{
        scope: "following",
        starts_at: DateTime.to_iso8601(moved),
        ends_at: moved |> DateTime.add(1, :hour) |> DateTime.to_iso8601(),
        title: "Κυριακάτικο τρέξιμο (νέα ώρα)"
      })
      |> json_response(200)

      after_edit = series.()

      Enum.zip(before, after_edit)
      |> Enum.with_index()
      |> Enum.each(fn {{was, now}, index} ->
        {:ok, was_start, _} = DateTime.from_iso8601(was["starts_at"])
        {:ok, now_start, _} = DateTime.from_iso8601(now["starts_at"])
        shift = if index == 0, do: 0, else: 30 * 60
        assert DateTime.diff(now_start, was_start) == shift
      end)

      assert hd(after_edit)["title"] == first["title"]
      assert Enum.all?(tl(after_edit), &(&1["title"] == "Κυριακάτικο τρέξιμο (νέα ώρα)"))

      drain()
      assert "community_event_changed" in types(ctx.member)

      [_, _, third, _] = after_edit

      ctx.as.(ctx.coach)
      |> send_json(:post, "#{ctx.staff}/#{third["id"]}/cancel", %{
        scope: "following",
        reason: "Καλοκαιρινή παύση"
      })
      |> json_response(200)

      assert [false, false, true, true] = Enum.map(series.(), & &1["cancelled"])

      assert %{"errors" => [%{"source" => %{"pointer" => "/scope"}}]} =
               ctx.as.(ctx.coach)
               |> send_json(:post, "#{ctx.staff}/#{first["id"]}/cancel", %{scope: "all"})
               |> json_response(422)
    end

    test "cancelling tells the people going, and closes the event to answers", ctx do
      event = new_event(ctx)
      rsvp(ctx, ctx.member, event, true) |> event_json()

      assert %{"event" => %{"cancelled" => true, "cancel_reason" => "Βροχή"}} =
               ctx.as.(ctx.coach)
               |> send_json(:post, "#{ctx.staff}/#{event["id"]}/cancel", %{reason: "Βροχή"})
               |> json_response(200)

      assert %{"code" => "event_cancelled"} =
               rsvp(ctx, ctx.other, event, true) |> json_response(409)

      drain()
      assert "community_event_cancelled" in types(ctx.member)
    end

    test "the reminder goes once, two hours before", ctx do
      event = new_event(ctx, %{starts_at: at(100), ends_at: at(160)})
      rsvp(ctx, ctx.member, event, true) |> event_json()
      context = %{organization_id: ctx.organization.id}

      EventReminders.sweep(context, DateTime.utc_now())
      EventReminders.sweep(context, DateTime.utc_now())
      drain()

      assert ["community_event_reminder"] =
               ctx.member |> types() |> Enum.filter(&(&1 == "community_event_reminder"))
    end
  end
end
