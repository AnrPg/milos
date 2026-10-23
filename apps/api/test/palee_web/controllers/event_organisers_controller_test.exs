defmodule PaleeWeb.EventOrganisersControllerTest do
  @moduledoc """
  ADR-185 (M2): «Διοργάνωση ως» (a person's own events through a hidden
  organiser organisation), co-hosting by request and answer, refunds, and
  the organiser console's Οικονομικά and Αναλυτικά.
  """

  use PaleeWeb.ConnCase, async: false

  import Ecto.Query
  import Palee.TestFixtures

  alias Palee.Application.{
    OrganiserCleanup,
    PublishBoxPublicProfile,
    TenantDefaults,
    UpdateBoxPublicProfile
  }

  alias Palee.Community.{Event, EventViewMark, Post}
  alias Palee.{Notifications, Organizations, Repo}
  alias Palee.Organizations.{Organization, OrganizationMembership}

  setup %{conn: conn} do
    start_supervised!(
      {Oban, Keyword.put(Application.fetch_env!(:palee, Oban), :testing, :manual)}
    )

    as = fn user -> put_bearer_token(conn, user) end
    host_box = published_box!("Host Box")
    cohost_box = published_box!("Cohost Box")

    %{
      as: as,
      host: host_box,
      cohost: cohost_box,
      person: user_fixture(),
      follower: user_fixture(),
      visitor: user_fixture()
    }
  end

  defp published_box!(name) do
    {:ok, organization} =
      Organizations.create_organization(%{name: "#{name} #{System.unique_integer([:positive])}"})

    owner = member!(organization, :owner)
    {:ok, owner_context} = Organizations.resolve_tenant_context(owner, organization.slug)

    {:ok, profile} =
      UpdateBoxPublicProfile.call(owner_context, %{
        "about" => "Έλα να γνωριστούμε.",
        "disciplines" => ["crossfit"]
      })

    {:ok, _profile} =
      PublishBoxPublicProfile.publish(owner_context, %{"lock_version" => profile.lock_version})

    %{
      organization: organization,
      slug: organization.slug,
      owner: owner,
      member: member!(organization, :member),
      admin: "/api/org/#{organization.slug}/admin/community"
    }
  end

  defp member!(organization, role) do
    user = user_fixture()

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

  defp own_event(ctx, user, attrs \\ %{}) do
    ctx.as.(user)
    |> send_json(
      :post,
      "/api/me/events",
      Map.merge(
        %{
          title: "Τρέξιμο στον Φιλοπάππου",
          starts_at: at(2 * 24 * 60),
          ends_at: at(2 * 24 * 60 + 60),
          place_name: "Λόφος Φιλοπάππου",
          latitude: 37.9681,
          longitude: 23.7197,
          audience: "open"
        },
        attrs
      )
    )
  end

  defp box_event(ctx, box, attrs \\ %{}) do
    ctx.as.(box.owner)
    |> send_json(
      :post,
      "/api/me/events",
      Map.merge(
        %{
          host: box.organization.id,
          title: "Open WOD",
          starts_at: at(2 * 24 * 60),
          ends_at: at(2 * 24 * 60 + 60),
          place_name: "Το box",
          audience: "open",
          price_cents: 1500
        },
        attrs
      )
    )
    |> json_response(201)
    |> Map.fetch!("event")
  end

  defp drain, do: Oban.drain_queue(queue: :notifications, with_safety: false)

  defp types(user), do: Notifications.list_for_user(user.id) |> Enum.map(&to_string(&1.type))

  defp end_event(event_id) do
    Repo.update_all(
      from(e in Event, where: e.id == ^event_id),
      set: [
        starts_at: DateTime.add(DateTime.utc_now(), -3, :hour),
        ends_at: DateTime.add(DateTime.utc_now(), -2, :hour)
      ]
    )
  end

  describe "hosting as yourself" do
    test "«Ως εγώ» creates a hidden one-person organiser organisation, once", ctx do
      assert %{"hosts" => [%{"kind" => "self", "organization_id" => nil, "clubs" => []}]} =
               ctx.as.(ctx.person) |> get("/api/me/event-hosts") |> json_response(200)

      assert %{"event" => event, "occurrences" => 1} =
               own_event(ctx, ctx.person) |> json_response(201)

      assert %{
               "audience" => "open",
               "open_to_non_members" => true,
               "channel_id" => nil,
               "can_manage" => true,
               "host" => %{"kind" => "person", "person" => %{"id" => person_id}, "slug" => nil}
             } = event

      assert person_id == ctx.person.id

      organization = Repo.get!(Organization, event["organization_id"])
      assert organization.provider_kind == "organiser"

      # A second event reuses it.
      assert %{"event" => %{"organization_id" => same}} =
               own_event(ctx, ctx.person, %{title: "Δεύτερο"}) |> json_response(201)

      assert same == organization.id

      # It never shows as a gym membership, a club or a provider.
      memberships = ctx.as.(ctx.person) |> get("/api/memberships") |> json_response(200)
      assert memberships == []

      assert %{"clubs" => clubs} =
               ctx.as.(ctx.person) |> get("/api/me/clubs") |> json_response(200)

      refute Enum.any?(clubs, &(&1["organization_id"] == organization.id))

      assert %{"hosts" => [%{"kind" => "self", "organization_id" => ^same}]} =
               ctx.as.(ctx.person) |> get("/api/me/event-hosts") |> json_response(200)

      # Anyone signed in sees an open event and comes.
      assert %{"event" => %{"my" => %{"status" => "going", "source" => "open"}}} =
               ctx.as.(ctx.visitor)
               |> send_json(:put, "/api/me/events/#{event["id"]}/rsvp", %{going: true})
               |> json_response(200)

      # Its host runs it from the organiser console like any box.
      assert %{"event" => %{"attendees" => %{"going" => [_]}}} =
               ctx.as.(ctx.person)
               |> get("/api/org/#{organization.slug}/admin/community/events/#{event["id"]}")
               |> json_response(200)
    end

    test "a bad form leaves no organisation behind", ctx do
      assert own_event(ctx, ctx.person, %{title: ""}) |> json_response(422)

      refute Repo.exists?(
               from(o in Organization,
                 join: m in OrganizationMembership,
                 on: m.organization_id == o.id,
                 where: o.provider_kind == "organiser" and m.user_id == ^ctx.person.id
               )
             )
    end

    test "a person's own event is never a group's and invitation-only is by the host's link",
         ctx do
      assert %{"event" => event} =
               own_event(ctx, ctx.person, %{audience: "group"}) |> json_response(201)

      assert %{"audience" => "club", "open_to_non_members" => false} = event

      # Not open: a stranger can't see it, but the host's link lets them in.
      assert ctx.as.(ctx.visitor) |> get("/api/me/events/#{event["id"]}") |> json_response(404)

      assert %{"host" => true, "guests_left" => nil, "token" => token} =
               ctx.as.(ctx.person)
               |> post("/api/me/events/#{event["id"]}/invites")
               |> json_response(201)

      assert %{"event" => %{"invitation" => %{"usable" => true}}} =
               ctx.as.(ctx.visitor)
               |> get("/api/me/events/#{event["id"]}?invite=#{token}")
               |> json_response(200)

      assert %{"event" => %{"my" => %{"status" => "going"}}} =
               ctx.as.(ctx.visitor)
               |> send_json(:put, "/api/me/events/#{event["id"]}/rsvp", %{
                 going: true,
                 invite_token: token
               })
               |> json_response(200)
    end

    test "an organiser organisation without events is archived after a day and comes back",
         ctx do
      {:ok, organization, true} =
        Organizations.ensure_organiser_organization(ctx.person, %{name: "Μαρία"},
          seed_defaults: TenantDefaults.organiser("Μαρία")
        )

      assert {:ok, %{archived: 0}} = OrganiserCleanup.call()

      Repo.update_all(from(o in Organization, where: o.id == ^organization.id),
        set: [inserted_at: DateTime.add(DateTime.utc_now(), -2, :day)]
      )

      assert {:ok, %{archived: archived}} = OrganiserCleanup.call()
      assert archived >= 1
      assert Repo.get!(Organization, organization.id).status == :archived

      assert %{"event" => %{"organization_id" => same}} =
               own_event(ctx, ctx.person) |> json_response(201)

      assert same == organization.id
      assert Repo.get!(Organization, organization.id).status == :active

      # One with an event is never swept.
      Repo.update_all(from(o in Organization, where: o.id == ^organization.id),
        set: [inserted_at: DateTime.add(DateTime.utc_now(), -2, :day)]
      )

      OrganiserCleanup.call()
      assert Repo.get!(Organization, organization.id).status == :active
    end

    test "creating is rate limited", ctx do
      for n <- 1..5 do
        assert own_event(ctx, ctx.person, %{title: "Event #{n}"}) |> json_response(201)
      end

      assert %{"code" => "event_rate_limited"} =
               own_event(ctx, ctx.person, %{title: "One too many"}) |> json_response(429)
    end

    test "an open event goes to the host's followers' feed; a block hides it", ctx do
      assert %{"status" => "requested"} =
               ctx.as.(ctx.follower)
               |> send_json(:post, "/api/me/follows", %{
                 target_type: "user",
                 target_id: ctx.person.id
               })
               |> json_response(200)

      assert %{"entries" => [%{"follow_id" => follow_id}]} =
               ctx.as.(ctx.person) |> get("/api/me/follow-requests") |> json_response(200)

      assert ctx.as.(ctx.person)
             |> post("/api/me/follow-requests/#{follow_id}/accept")
             |> response(204)

      assert %{"event" => %{"id" => event_id}} = own_event(ctx, ctx.person) |> json_response(201)

      assert %{"posts" => posts} =
               ctx.as.(ctx.follower) |> get("/api/me/feed") |> json_response(200)

      assert %{"origin" => "profile", "event" => %{"id" => ^event_id}} =
               Enum.find(posts, &(&1["attachment_type"] == "event"))
    end

    test "page opens are counted once a day per person, never the host's", ctx do
      assert %{"event" => %{"id" => event_id, "organization_id" => org_id}} =
               own_event(ctx, ctx.person) |> json_response(201)

      view = fn user ->
        ctx.as.(user) |> post("/api/me/events/#{event_id}/views") |> json_response(200)
      end

      assert %{"counted" => false} = view.(ctx.person)
      assert %{"counted" => true} = view.(ctx.visitor)
      assert %{"counted" => true} = view.(ctx.visitor)
      assert %{"counted" => true} = view.(ctx.follower)

      # The marks are keyed hashes, never a person's id.
      marks = Repo.all(from(m in EventViewMark, where: m.event_id == ^event_id))
      assert length(marks) == 2
      refute Enum.any?(marks, &(&1.viewer_key in [ctx.visitor.id, ctx.follower.id]))

      slug = Repo.get!(Organization, org_id).slug

      assert %{
               "events" => [%{"views" => 3, "viewers" => 2, "rsvps" => 0}],
               "totals" => %{"views" => 3}
             } =
               ctx.as.(ctx.person)
               |> get("/api/org/#{slug}/admin/community/event-analytics")
               |> json_response(200)
    end
  end

  describe "hosting as a business" do
    test "the box is offered with its clubs and the event goes in its gym club", ctx do
      assert %{"hosts" => [%{"kind" => "self"}, business]} =
               ctx.as.(ctx.host.owner) |> get("/api/me/event-hosts") |> json_response(200)

      assert %{"kind" => "business", "clubs" => [%{"kind" => "gym"} | _]} = business
      assert business["id"] == ctx.host.organization.id

      event = box_event(ctx, ctx.host)
      assert event["organization_id"] == ctx.host.organization.id
      assert %{"kind" => "business", "slug" => slug} = event["host"]
      assert slug == ctx.host.slug

      # A plain member can't host as the box.
      assert %{"code" => "forbidden"} =
               ctx.as.(ctx.host.member)
               |> send_json(:post, "/api/me/events", %{
                 host: ctx.host.organization.id,
                 title: "Όχι",
                 starts_at: at(60),
                 ends_at: at(120),
                 place_name: "Κάπου"
               })
               |> json_response(403)
    end
  end

  describe "co-hosts asked as the event is created (ADR-185)" do
    test "a business's event and its co-host requests are made together; an unknown box is reported",
         ctx do
      third = published_box!("Third Box")

      assert %{"event" => event, "occurrences" => 2, "cohost_failures" => failures} =
               ctx.as.(ctx.host.owner)
               |> send_json(:post, "/api/me/events", %{
                 host: ctx.host.organization.id,
                 title: "Open WOD",
                 starts_at: at(2 * 24 * 60),
                 ends_at: at(2 * 24 * 60 + 60),
                 # The last day is gym-local (ADR-176): the box's date of the 2nd start,
                 # so the run does not lose it late in the UTC evening.
                 repeat_until:
                   DateTime.utc_now()
                   |> DateTime.add(9, :day)
                   |> Palee.TimeZones.ZonedTime.local_date(
                     Palee.TimeZones.ZonedTime.default_zone()
                   )
                   |> Date.to_iso8601(),
                 place_name: "Το box",
                 audience: "open",
                 cohost_slugs: [ctx.cohost.slug, "/b/#{third.slug}", "no-such-box"]
               })
               |> json_response(201)

      assert failures == [%{"slug" => "no-such-box", "code" => "box_not_found"}]

      # Every occurrence asks both boxes, pending.
      rows =
        Repo.all(
          from c in Palee.Community.EventCohost,
            join: e in Event,
            on: e.id == c.event_id,
            where: e.organization_id == ^ctx.host.organization.id,
            select: {c.cohost_organization_id, c.status}
        )

      assert length(rows) == 4
      assert Enum.all?(rows, fn {_box, status} -> status == "pending" end)

      assert rows |> Enum.map(&elem(&1, 0)) |> Enum.uniq() |> Enum.sort() ==
               Enum.sort([ctx.cohost.organization.id, third.organization.id])

      assert %{"cohosts" => [_, _]} =
               ctx.as.(ctx.host.owner)
               |> get("#{ctx.host.admin}/events/#{event["id"]}/cohosts")
               |> json_response(200)

      # One request notice per box, as a later invite would send.
      drain()
      assert Enum.count(types(ctx.cohost.owner), &(&1 == "community_event_cohost_request")) == 1
      assert "community_event_cohost_request" in types(third.owner)
    end

    test "a refused co-host list creates nothing", ctx do
      count = fn ->
        Repo.aggregate(
          from(e in Event, where: e.organization_id == ^ctx.host.organization.id),
          :count
        )
      end

      body = fn slugs ->
        %{
          host: ctx.host.organization.id,
          title: "Open WOD",
          starts_at: at(2 * 24 * 60),
          ends_at: at(2 * 24 * 60 + 60),
          place_name: "Το box",
          cohost_slugs: slugs
        }
      end

      post = fn slugs ->
        ctx.as.(ctx.host.owner) |> send_json(:post, "/api/me/events", body.(slugs))
      end

      assert %{"code" => "cannot_cohost_own_event"} =
               post.([ctx.cohost.slug, ctx.host.slug]) |> json_response(422)

      assert %{"code" => "duplicate_cohost"} =
               post.([ctx.cohost.slug, "b/#{ctx.cohost.slug}"]) |> json_response(422)

      assert %{"code" => "invalid_cohosts"} = post.(["not a slug"]) |> json_response(422)

      assert count.() == 0
    end

    test "a person's own event and the staff route follow the same rules", ctx do
      # The box's gym club exists once it has hosted.
      box_event(ctx, ctx.host)

      # A person's own event: their organiser organisation holds manage_events.
      assert %{"cohost_failures" => []} =
               own_event(ctx, ctx.person, %{cohost_slugs: [ctx.cohost.slug]})
               |> json_response(201)

      # The staff route runs the same rules.
      assert %{"code" => "cannot_cohost_own_event"} =
               ctx.as.(ctx.host.owner)
               |> send_json(:post, "#{ctx.host.admin}/events", %{
                 club_id: gym_club_id(ctx.host),
                 title: "Open WOD",
                 starts_at: at(2 * 24 * 60),
                 ends_at: at(2 * 24 * 60 + 60),
                 place_name: "Το box",
                 cohost_slugs: [ctx.host.slug]
               })
               |> json_response(422)

      assert %{"cohost_failures" => []} =
               ctx.as.(ctx.host.owner)
               |> send_json(:post, "#{ctx.host.admin}/events", %{
                 club_id: gym_club_id(ctx.host),
                 title: "Open WOD",
                 starts_at: at(2 * 24 * 60),
                 ends_at: at(2 * 24 * 60 + 60),
                 place_name: "Το box",
                 cohost_slugs: [ctx.cohost.slug]
               })
               |> json_response(201)
    end
  end

  describe "the event store (ADR-185)" do
    test "writes an event's occurrences and their co-host requests together, or neither", ctx do
      row = Repo.get!(Event, box_event(ctx, ctx.host)["id"])

      attrs =
        row
        |> Map.from_struct()
        |> Map.take(Event.editable_fields() ++ [:organization_id, :club_id, :created_by_id])
        |> Map.merge(%{title: "Rolled back", starts_at: row.starts_at, ends_at: row.ends_at})

      # The host can't co-host its own event: the second insert fails, so the first goes too.
      assert {:error, %Ecto.Changeset{}} =
               Palee.Infrastructure.Community.EctoEventStore.insert_events_with_cohosts(
                 %{},
                 [attrs, attrs],
                 %{cohost_organization_ids: [ctx.host.organization.id], invited_by_id: nil}
               )

      refute Repo.exists?(from e in Event, where: e.title == "Rolled back")

      assert {:ok, %{events: [_, _], cohosts: [_, _]}} =
               Palee.Infrastructure.Community.EctoEventStore.insert_events_with_cohosts(
                 %{},
                 [attrs, attrs],
                 %{cohost_organization_ids: [ctx.cohost.organization.id], invited_by_id: nil}
               )
    end
  end

  defp gym_club_id(box) do
    Repo.one!(
      from c in Palee.Community.Club,
        where: c.organization_id == ^box.organization.id and c.kind == "gym",
        select: c.id,
        limit: 1
    )
  end

  describe "co-hosting" do
    test "request, accept, show on the co-host's page and feed, then its own trial offer",
         ctx do
      event = box_event(ctx, ctx.host)
      cohosts = "#{ctx.host.admin}/events/#{event["id"]}/cohosts"

      assert %{"code" => "box_not_found"} =
               ctx.as.(ctx.host.owner)
               |> send_json(:post, cohosts, %{slug: "no-such-box"})
               |> json_response(404)

      assert %{"code" => "cannot_cohost_own_event"} =
               ctx.as.(ctx.host.owner)
               |> send_json(:post, cohosts, %{slug: ctx.host.slug})
               |> json_response(422)

      assert %{"cohosts" => [%{"status" => "pending", "box" => %{"slug" => cohost_slug}}]} =
               ctx.as.(ctx.host.owner)
               |> send_json(:post, cohosts, %{slug: ctx.cohost.slug})
               |> json_response(200)

      assert cohost_slug == ctx.cohost.slug

      assert %{"code" => "already_invited"} =
               ctx.as.(ctx.host.owner)
               |> send_json(:post, cohosts, %{slug: ctx.cohost.slug})
               |> json_response(409)

      drain()
      assert "community_event_cohost_request" in types(ctx.cohost.owner)

      # The co-host's staff see the request; its members can't.
      requests = "#{ctx.cohost.admin}/cohost-requests"

      assert %{"requests" => [%{"id" => request_id, "answerable" => true} = request]} =
               ctx.as.(ctx.cohost.owner) |> get(requests) |> json_response(200)

      assert request["event"]["id"] == event["id"]
      assert request["host"]["slug"] == ctx.host.slug
      assert ctx.as.(ctx.cohost.member) |> get(requests) |> json_response(403)

      # Before accepting, the event is not on its page.
      assert %{"events" => []} =
               ctx.as.(ctx.visitor)
               |> get("/api/boxes/#{ctx.cohost.slug}/events")
               |> json_response(200)

      assert %{"requests" => [%{"status" => "accepted"}]} =
               ctx.as.(ctx.cohost.owner)
               |> send_json(:post, "#{requests}/#{request_id}/answer", %{answer: "accepted"})
               |> json_response(200)

      assert %{"code" => "not_pending"} =
               ctx.as.(ctx.cohost.owner)
               |> send_json(:post, "#{requests}/#{request_id}/answer", %{answer: "declined"})
               |> json_response(409)

      drain()
      assert "community_event_cohost_answered" in types(ctx.host.owner)

      # On its page's Events tab and in its members' feed, naming both.
      assert %{"events" => [%{"id" => id, "cohosts" => [%{"slug" => ^cohost_slug}]}]} =
               ctx.as.(ctx.visitor)
               |> get("/api/boxes/#{ctx.cohost.slug}/events")
               |> json_response(200)

      assert id == event["id"]

      assert %Post{attachment_type: "event", organization_id: cohost_org} =
               Repo.one(
                 from(p in Post,
                   where:
                     p.organization_id == ^ctx.cohost.organization.id and
                       p.attachment_id == ^event["id"]
                 )
               )

      assert cohost_org == ctx.cohost.organization.id

      assert %{"posts" => posts} =
               ctx.as.(ctx.cohost.member) |> get("/api/me/feed") |> json_response(200)

      assert %{"event" => %{"id" => ^id}} =
               Enum.find(posts, &(&1["attachment_type"] == "event"))

      # The co-host's members belong to the audience of a club event too.
      assert %{"event" => %{"my" => %{"status" => "going"}}} =
               ctx.as.(ctx.cohost.member)
               |> send_json(:put, "/api/me/events/#{id}/rsvp", %{going: true})
               |> json_response(200)

      # The visitor comes; after the event the co-host offers its own trial.
      ctx.as.(ctx.visitor)
      |> send_json(:put, "/api/me/events/#{id}/rsvp", %{going: true})
      |> json_response(200)

      for user <- [ctx.visitor, ctx.cohost.member] do
        ctx.as.(ctx.host.owner)
        |> send_json(:put, "#{ctx.host.admin}/events/#{id}/attendees/#{user.id}/check-in", %{
          checked_in: true
        })
        |> json_response(200)
      end

      offer = fn -> ctx.as.(ctx.cohost.owner) |> post("#{requests}/#{request_id}/trial-offer") end
      assert %{"code" => "event_not_over"} = offer.() |> json_response(409)

      end_event(id)
      assert %{"code" => "trials_disabled"} = offer.() |> json_response(422)

      ctx.as.(ctx.cohost.owner)
      |> send_json(:put, "/api/org/#{ctx.cohost.slug}/admin/trial-policy", %{enabled: true})
      |> json_response(200)

      assert %{"sent" => 1} = offer.() |> json_response(200)
      assert %{"code" => "trial_offer_already_sent"} = offer.() |> json_response(409)

      drain()

      [notice] =
        ctx.visitor.id
        |> Notifications.list_for_user()
        |> Enum.filter(&(to_string(&1.type) == "community_event_trial_offer"))

      assert notice.payload["url"] =~ "/b/#{ctx.cohost.slug}?trial=1&referral_event_id=#{id}"
      refute "community_event_trial_offer" in types(ctx.cohost.member)
    end

    test "the host takes a co-host off and the event leaves its page", ctx do
      event = box_event(ctx, ctx.host)
      cohosts = "#{ctx.host.admin}/events/#{event["id"]}/cohosts"

      ctx.as.(ctx.host.owner)
      |> send_json(:post, cohosts, %{slug: ctx.cohost.slug})
      |> json_response(200)

      %{"requests" => [%{"id" => request_id}]} =
        ctx.as.(ctx.cohost.owner)
        |> get("#{ctx.cohost.admin}/cohost-requests")
        |> json_response(200)

      ctx.as.(ctx.cohost.owner)
      |> send_json(:post, "#{ctx.cohost.admin}/cohost-requests/#{request_id}/answer", %{
        answer: "accepted"
      })
      |> json_response(200)

      assert %{"cohosts" => [%{"id" => cohost_id, "status" => "accepted"}]} =
               ctx.as.(ctx.host.owner) |> get(cohosts) |> json_response(200)

      assert %{"cohosts" => [%{"status" => "removed"}]} =
               ctx.as.(ctx.host.owner)
               |> delete("#{cohosts}/#{cohost_id}")
               |> json_response(200)

      assert %{"events" => []} =
               ctx.as.(ctx.visitor)
               |> get("/api/boxes/#{ctx.cohost.slug}/events")
               |> json_response(200)

      # Asked again after a removal, it is pending once more.
      assert %{"cohosts" => [%{"status" => "pending"}]} =
               ctx.as.(ctx.host.owner)
               |> send_json(:post, cohosts, %{slug: ctx.cohost.slug})
               |> json_response(200)
    end
  end

  describe "the organiser console" do
    test "refunds and Οικονομικά per event and in total", ctx do
      event = box_event(ctx, ctx.host)
      base = "#{ctx.host.admin}/events/#{event["id"]}"

      for user <- [ctx.visitor, ctx.follower] do
        ctx.as.(user)
        |> send_json(:put, "/api/me/events/#{event["id"]}/rsvp", %{going: true})
        |> json_response(200)
      end

      ctx.as.(ctx.host.owner)
      |> send_json(:put, "#{base}/attendees/#{ctx.visitor.id}/paid", %{payment_method: "cash"})
      |> json_response(200)

      assert %{"code" => "not_paid"} =
               ctx.as.(ctx.host.owner)
               |> send_json(:put, "#{base}/attendees/#{ctx.follower.id}/refund", %{})
               |> json_response(409)

      assert %{"code" => "invalid_refund"} =
               ctx.as.(ctx.host.owner)
               |> send_json(:put, "#{base}/attendees/#{ctx.visitor.id}/refund", %{
                 amount_cents: 5000
               })
               |> json_response(422)

      assert %{"event" => %{"attendees" => %{"going" => going}}} =
               ctx.as.(ctx.host.owner)
               |> send_json(:put, "#{base}/attendees/#{ctx.visitor.id}/refund", %{
                 amount_cents: 500
               })
               |> json_response(200)

      assert %{"refund_cents" => 500, "refunded_at" => refunded_at} =
               Enum.find(going, &(&1["person"]["id"] == ctx.visitor.id))

      assert refunded_at

      assert %{"code" => "already_refunded"} =
               ctx.as.(ctx.host.owner)
               |> send_json(:put, "#{base}/attendees/#{ctx.visitor.id}/refund", %{})
               |> json_response(409)

      assert %{
               "events" => [
                 %{
                   "paid_cents" => 1500,
                   "refunded_cents" => 500,
                   "net_cents" => 1000,
                   "outstanding_count" => 1,
                   "outstanding_cents" => 1500
                 }
               ],
               "totals" => [%{"currency" => "EUR", "events" => 1, "net_cents" => 1000}]
             } =
               ctx.as.(ctx.host.owner)
               |> get("#{ctx.host.admin}/event-finances")
               |> json_response(200)

      # Members of the box see none of it.
      assert ctx.as.(ctx.host.member)
             |> get("#{ctx.host.admin}/event-finances")
             |> json_response(403)
    end
  end
end
