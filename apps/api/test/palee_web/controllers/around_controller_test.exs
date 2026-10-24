defmodule PaleeWeb.AroundControllerTest do
  @moduledoc """
  ADR-154 (P2-M6, board 9): Γύρω μου against real PostGIS, as the RLS
  runtime role: sections by kind ordered by time or distance, every filter,
  only public items, people's posts at their neighbourhood's centroid,
  map pins, wider counts, «Η περιοχή μου» and the daily saved-filter alert.
  """

  use PaleeWeb.ConnCase, async: false

  import Ecto.Query
  import Palee.TestFixtures

  alias Palee.Application.{
    AroundAlerts,
    ClubScope,
    OpenClubs,
    PublishBoxPublicProfile,
    UpdateBoxPublicProfile
  }

  alias Palee.Community.{Channel, Event, Post, ProfilePost}
  alias Palee.{Facility, Organizations, Repo, Trials}
  alias Palee.Notifications.Notification

  # The search point (rounded already) and what sits around it.
  @here %{type: "point", latitude: 38.01, longitude: 23.738}

  setup %{conn: conn} do
    start_supervised!(
      {Oban, Keyword.put(Application.fetch_env!(:palee, Oban), :testing, :manual)}
    )

    kypseli = neighbourhood("athens-kypseli")
    patisia = neighbourhood("athens-patisia")

    alpha =
      gym("Alpha Box", {38.006, 23.738},
        disciplines: ["crossfit"],
        audiences: ["beginners"],
        amenities: ["showers", "wheelchair_accessible"],
        languages: ["el", "fr"]
      )

    beta =
      gym("Beta Yoga", {38.022, 23.733},
        disciplines: ["yoga"],
        audiences: ["women_only"],
        amenities: ["showers"],
        trial: true
      )

    far = gym("Glyfada Strength", {37.865, 23.754}, disciplines: ["strength"])
    hidden = gym("Draft Box", {38.009, 23.737}, publish: false)

    as = fn user -> put_bearer_token(conn, user) end

    %{
      as: as,
      kypseli: kypseli,
      patisia: patisia,
      alpha: alpha,
      beta: beta,
      far: far,
      hidden: hidden,
      visitor: user_fixture()
    }
  end

  # ------------------------------------------------------------- fixtures

  defp neighbourhood(slug) do
    Repo.one!(
      from n in "places_neighbourhoods",
        where: n.slug == ^slug,
        select: %{id: type(n.id, :binary_id), latitude: n.latitude, longitude: n.longitude}
    )
  end

  defp gym(name, {latitude, longitude}, opts) do
    {:ok, organization} =
      Organizations.create_organization(%{name: "#{name} #{System.unique_integer([:positive])}"})

    owner = user_fixture()
    add_member(organization, owner, :owner)
    {:ok, context} = Organizations.resolve_tenant_context(owner, organization.slug)

    {:ok, _location} =
      Facility.create_location(context, %{
        "name" => name,
        "address" => "Οδός 1",
        "latitude" => latitude,
        "longitude" => longitude,
        "neighbourhood" => "Κυψέλη",
        "city" => "Αθήνα"
      })

    if Keyword.get(opts, :publish, true) do
      {:ok, profile} =
        UpdateBoxPublicProfile.call(context, %{
          "about" => "Καλώς ήρθες.",
          "disciplines" => Keyword.get(opts, :disciplines, []),
          "audiences" => Keyword.get(opts, :audiences, []),
          "amenities" => Keyword.get(opts, :amenities, []),
          "languages" => Keyword.get(opts, :languages, ["el", "en"])
        })

      {:ok, _profile} =
        PublishBoxPublicProfile.publish(context, %{"lock_version" => profile.lock_version})
    end

    if opts[:trial], do: {:ok, _policy} = Trials.update_policy(context, %{enabled: true})

    {:ok, club} = ClubScope.gym_club(context)

    channel_id =
      Repo.one!(from c in Channel, where: c.club_id == ^club.id, select: c.id, limit: 1)

    %{
      organization: organization,
      owner: owner,
      context: context,
      club_id: club.id,
      channel_id: channel_id,
      point: {latitude, longitude}
    }
  end

  defp add_member(organization, user, role) do
    {:ok, _membership} =
      Organizations.add_membership(%{
        organization_id: organization.id,
        user_id: user.id,
        role: role,
        status: :active,
        joined_at: DateTime.utc_now()
      })
  end

  defp event(gym, attrs) do
    now = DateTime.utc_now()
    starts_at = Map.get(attrs, :starts_at, DateTime.add(now, 2, :day))

    Repo.insert!(
      struct(
        Event,
        Map.merge(
          %{
            organization_id: gym.organization.id,
            club_id: gym.club_id,
            created_by_id: gym.owner.id,
            title: "Event",
            starts_at: starts_at,
            ends_at: DateTime.add(starts_at, 1, :hour),
            open_to_non_members: true
          },
          Map.delete(attrs, :starts_at)
        )
      )
    )
  end

  defp club_post(gym, audience, body) do
    Repo.insert!(%Post{
      organization_id: gym.organization.id,
      club_id: gym.club_id,
      channel_id: gym.channel_id,
      author_id: gym.owner.id,
      audience: audience,
      body: body
    })
  end

  defp profile_post(user, audience, body),
    do: Repo.insert!(%ProfilePost{user_id: user.id, audience: audience, body: body})

  defp open_club(gym, name) do
    {:ok, club} = OpenClubs.create(gym.context, %{name: name, join_policy: "open"})
    club
  end

  defp send_json(conn, method, path, body) do
    conn
    |> put_req_header("content-type", "application/json")
    |> dispatch(@endpoint, method, path, Jason.encode!(body))
  end

  defp search(ctx, user, body, status \\ 200) do
    ctx.as.(user)
    |> send_json(:post, "/api/around/search", Map.put_new(body, :origin, @here))
    |> json_response(status)
  end

  defp items(result, kind), do: get_in(result, ["sections", kind, "items"])

  defp names(result, "events"), do: result |> items("events") |> Enum.map(& &1["event"]["title"])
  defp names(result, "clubs"), do: result |> items("clubs") |> Enum.map(& &1["club"]["name"])
  defp names(result, "posts"), do: result |> items("posts") |> Enum.map(& &1["post"]["body"])

  defp names(result, "boxes"),
    do: result |> items("boxes") |> Enum.map(&(&1["box"]["name"] |> String.split() |> hd()))

  defp local_date(datetime),
    do:
      datetime |> DateTime.shift_zone!("Europe/Athens") |> DateTime.to_date() |> Date.to_iso8601()

  # ------------------------------------------------------------ sections

  describe "sections" do
    setup ctx do
      now = DateTime.utc_now()

      event(ctx.alpha, %{
        title: "Open WOD",
        latitude: 38.0105,
        longitude: 23.7385,
        place_name: "Πλατεία"
      })

      event(ctx.beta, %{
        title: "Sunrise flow",
        starts_at: DateTime.add(now, 1, :day),
        price_cents: 1000
      })

      event(ctx.alpha, %{title: "Members only", open_to_non_members: false})
      event(ctx.alpha, %{title: "Cancelled", cancelled_at: now})
      event(ctx.alpha, %{title: "Yesterday", starts_at: DateTime.add(now, -1, :day)})
      event(ctx.far, %{title: "Far away"})

      open_club(ctx.alpha, "Alpha runners")
      open_club(ctx.beta, "Beta walkers")
      open_club(ctx.far, "Far lifters")
      :ok
    end

    test "events soonest first, boxes trial-takers first, clubs nearest first, each with its distance",
         ctx do
      result = search(ctx, ctx.visitor, %{})

      assert result["origin"]["type"] == "point"
      # The nearest gazetteer place names the point; the point itself is not stored.
      assert is_binary(result["origin"]["label"])
      assert names(result, "events") == ["Sunrise flow", "Open WOD"]
      assert names(result, "boxes") == ["Beta", "Alpha"]
      assert names(result, "clubs") == ["Alpha runners", "Beta walkers"]
      assert result["sections"]["posts"] == nil
      assert result["sections"]["events"]["total"] == 2
      assert result["sections"]["boxes"]["placement"] == "category"

      [sunrise, wod] = items(result, "events")
      assert wod["distance_km"] == 0.1
      # An event without a place sits at its box's location.
      assert sunrise["distance_km"] == 1.4

      [beta, alpha] = items(result, "boxes")
      assert beta["box"]["takes_trials"]
      refute alpha["box"]["takes_trials"]
      assert alpha["distance_km"] == 0.4
      assert alpha["distance_km"] < beta["distance_km"]

      # The draft box never shows; neither does anything 16 km away.
      refute Enum.any?(items(result, "boxes"), &(&1["box"]["name"] =~ "Draft"))
      refute "Far lifters" in names(result, "clubs")
    end

    test "each filter narrows every kind it applies to", ctx do
      filtered = fn filter -> search(ctx, ctx.visitor, %{filter: filter}) end

      only = fn filter, kind -> filtered.(filter) |> names(kind) end

      assert only.(%{kinds: ["clubs"]}, "clubs") == ["Alpha runners", "Beta walkers"]
      assert filtered.(%{kinds: ["clubs"]})["sections"]["events"] == nil

      yoga = filtered.(%{disciplines: ["yoga"]})
      assert names(yoga, "events") == ["Sunrise flow"]
      assert names(yoga, "boxes") == ["Beta"]
      assert names(yoga, "clubs") == ["Beta walkers"]

      assert only.(%{audiences: ["beginners"]}, "boxes") == ["Alpha"]
      assert only.(%{languages: ["fr"]}, "boxes") == ["Alpha"]
      # Amenities must all be there.
      assert only.(%{amenities: ["showers"]}, "boxes") == ["Beta", "Alpha"]
      assert only.(%{amenities: ["showers", "wheelchair_accessible"]}, "boxes") == ["Alpha"]

      free = filtered.(%{cost: ["free"]})
      assert names(free, "events") == ["Open WOD"]
      assert free["sections"]["boxes"] == nil

      assert names(filtered.(%{cost: ["free"], max_price_cents: 1000}), "events") == [
               "Sunrise flow",
               "Open WOD"
             ]

      # A price range from €5 drops the free event and the (always free) clubs.
      priced = filtered.(%{min_price_cents: 500, max_price_cents: 2000})
      assert names(priced, "events") == ["Sunrise flow"]
      assert priced["sections"]["clubs"] == nil
      assert priced["filter"]["min_price_cents"] == 500
      assert names(filtered.(%{min_price_cents: 1500}), "events") == []
      assert names(filtered.(%{max_price_cents: 500}), "events") == ["Open WOD"]

      assert %{"errors" => _} =
               search(ctx, ctx.visitor, %{filter: %{min_price_cents: 2000, max_price_cents: 1000}}, 422)

      trial = filtered.(%{cost: ["trial"]})
      assert names(trial, "boxes") == ["Beta"]
      assert trial["sections"]["events"] == nil

      day = local_date(DateTime.add(DateTime.utc_now(), 1, :day))
      ranged = filtered.(%{when: "range", date_from: day, date_to: day})
      assert names(ranged, "events") == ["Sunrise flow"]

      assert names(filtered.(%{radius_km: 1.0}), "boxes") == ["Alpha"]
      assert names(filtered.(%{radius_km: 20.0}), "boxes") == ["Beta", "Alpha", "Glyfada"]

      assert %{"errors" => _} =
               search(ctx, ctx.visitor, %{filter: %{disciplines: ["weight_loss"]}}, 422)
    end

    test "people with a gym see other boxes collapsed and never their own", ctx do
      member = user_fixture()
      add_member(ctx.alpha.organization, member, :member)

      result = search(ctx, member, %{})
      assert result["sections"]["boxes"]["placement"] == "collapsed"
      assert names(result, "boxes") == ["Beta"]
    end

    test "a section pages on with its cursor", ctx do
      first =
        ctx.as.(ctx.visitor)
        |> send_json(:post, "/api/around/search/events", %{origin: @here, limit: 1})
        |> json_response(200)

      assert %{"kind" => "events", "total" => 2, "next_cursor" => cursor} = first
      assert [%{"event" => %{"title" => "Sunrise flow"}}] = first["items"]

      second =
        ctx.as.(ctx.visitor)
        |> send_json(:post, "/api/around/search/events", %{
          origin: @here,
          limit: 1,
          cursor: cursor
        })
        |> json_response(200)

      assert [%{"event" => %{"title" => "Open WOD"}}] = second["items"]
      assert second["next_cursor"] == nil

      ctx.as.(ctx.visitor)
      |> send_json(:post, "/api/around/search/events", %{origin: @here, cursor: "nope"})
      |> json_response(422)

      ctx.as.(ctx.visitor)
      |> send_json(:post, "/api/around/search/gyms", %{origin: @here})
      |> json_response(404)
    end

    test "map pins inside a viewport, same filter, people with a gym see no boxes", ctx do
      bbox = %{west: 23.70, south: 37.98, east: 23.78, north: 38.04}

      %{"pins" => pins, "truncated" => false} =
        ctx.as.(ctx.visitor)
        |> send_json(:post, "/api/around/pins", %{bbox: bbox})
        |> json_response(200)

      by_kind = Enum.group_by(pins, & &1["kind"], & &1["title"])
      assert Enum.sort(by_kind["events"]) == ["Open WOD", "Sunrise flow"]
      assert length(by_kind["boxes"]) == 2
      assert Enum.sort(by_kind["clubs"]) == ["Alpha runners", "Beta walkers"]

      wod = Enum.find(pins, &(&1["title"] == "Open WOD"))
      assert {wod["latitude"], wod["longitude"]} == {38.0105, 23.7385}

      member = user_fixture()
      add_member(ctx.beta.organization, member, :member)

      member_pins =
        ctx.as.(member)
        |> send_json(:post, "/api/around/pins", %{bbox: bbox})
        |> json_response(200)
        |> Map.fetch!("pins")

      refute Enum.any?(member_pins, &(&1["kind"] == "boxes"))

      ctx.as.(ctx.visitor)
      |> send_json(:post, "/api/around/pins", %{
        bbox: %{west: 22.0, south: 37.0, east: 24.0, north: 39.0}
      })
      |> json_response(422)
    end

    test "little nearby comes with counts at 10 and 25 km", ctx do
      result = search(ctx, ctx.visitor, %{filter: %{kinds: ["boxes"]}})

      assert [
               %{"radius_km" => 10.0, "total" => 2, "by_kind" => %{"boxes" => 2}},
               %{"radius_km" => 25.0, "total" => 3, "by_kind" => %{"boxes" => 3}}
             ] = result["wider"]

      assert search(ctx, ctx.visitor, %{
               filter: %{kinds: ["events", "boxes", "clubs"], radius_km: 3.0}
             })[
               "wider"
             ] == []
    end
  end

  # --------------------------------------------------------------- posts

  describe "posts" do
    test "box posts and the posts of people who opted in, at their neighbourhood's centroid",
         ctx do
      club_post(ctx.alpha, "public", "Box news")
      club_post(ctx.alpha, "club_channel", "Members chat")
      club_post(ctx.hidden, "public", "Draft news")

      shown = user_fixture()
      quiet = user_fixture()

      for user <- [shown, quiet] do
        ctx.as.(user)
        |> send_json(:put, "/api/me/around/area", %{neighbourhood_ids: [ctx.kypseli.id]})
        |> json_response(200)
      end

      assert %{"visible" => true, "has_area" => true} =
               ctx.as.(shown)
               |> send_json(:put, "/api/me/social/around-visibility", %{visible: true})
               |> json_response(200)

      profile_post(shown, "public", "Morning run")
      profile_post(shown, "followers", "For followers")
      profile_post(quiet, "public", "Not around")

      result = search(ctx, ctx.visitor, %{filter: %{kinds: ["posts"]}})
      assert Enum.sort(names(result, "posts")) == ["Box news", "Morning run"]

      person = Enum.find(items(result, "posts"), &(&1["post"]["body"] == "Morning run"))
      # 38.010 → Kypseli's centroid at 38.001: one kilometre, never the person's own spot.
      assert person["distance_km"] == 1.0
      refute inspect(person) =~ "latitude"

      # A person's post carries no tags, so any tag filter leaves it out.
      tagged = search(ctx, ctx.visitor, %{filter: %{kinds: ["posts"], disciplines: ["crossfit"]}})
      assert names(tagged, "posts") == ["Box news"]

      # Turning it off hides them again.
      ctx.as.(shown)
      |> send_json(:put, "/api/me/social/around-visibility", %{visible: false})
      |> json_response(200)

      assert names(search(ctx, ctx.visitor, %{filter: %{kinds: ["posts"]}}), "posts") == [
               "Box news"
             ]
    end

    test "the visibility setting starts off and shows in the social summary", ctx do
      assert %{"around_visibility" => %{"visible" => false, "has_area" => false}} =
               ctx.as.(ctx.visitor) |> get("/api/me/social") |> json_response(200)
    end
  end

  # ------------------------------------------------------------- origins

  describe "origins and «Η περιοχή μου»" do
    test "the saved area is private and starts searches; the box is the fallback", ctx do
      assert %{"neighbourhoods" => [%{"name" => "Κυψέλη", "latitude" => 38.001} | _]} =
               ctx.as.(ctx.visitor)
               |> get("/api/places/neighbourhoods?q=" <> URI.encode_www_form("ΚΥΨΕΛΗ"))
               |> json_response(200)

      assert %{"origin" => %{"type" => "box"}} =
               search(ctx, ctx.alpha.owner, %{origin: nil})

      ctx.as.(ctx.visitor)
      |> send_json(:post, "/api/around/search", %{})
      |> json_response(422)

      assert %{"neighbourhoods" => [%{"id" => first}, _]} =
               ctx.as.(ctx.visitor)
               |> send_json(:put, "/api/me/around/area", %{
                 neighbourhood_ids: [ctx.kypseli.id, ctx.patisia.id]
               })
               |> json_response(200)

      assert first == ctx.kypseli.id

      assert %{"neighbourhoods" => []} =
               ctx.as.(user_fixture()) |> get("/api/me/around/area") |> json_response(200)

      result =
        ctx.as.(ctx.visitor)
        |> send_json(:post, "/api/around/search", %{})
        |> json_response(200)

      assert %{"type" => "area", "neighbourhood_ids" => [_, _]} = result["origin"]

      for bad <- [
            ["nope"],
            [Ecto.UUID.generate()],
            List.duplicate(ctx.kypseli.id, 1) ++ Enum.map(1..5, fn _ -> Ecto.UUID.generate() end)
          ] do
        ctx.as.(ctx.visitor)
        |> send_json(:put, "/api/me/around/area", %{neighbourhood_ids: bad})
        |> json_response(422)
      end
    end

    test "a device position is rounded and never stored; places come from the gazetteer or the geocoder",
         ctx do
      result =
        search(ctx, ctx.visitor, %{
          origin: %{type: "point", latitude: 38.0104567, longitude: 23.7381234},
          remember: false
        })

      assert %{"latitude" => 38.01, "longitude" => 23.738} = result["origin"]

      # `remember: false` leaves the last-used filter alone.
      assert %{"last_used" => nil} =
               ctx.as.(ctx.visitor) |> get("/api/me/filters/around_me") |> json_response(200)

      assert %{"origin" => %{"type" => "place", "label" => "Κυψέλη"}} =
               search(ctx, ctx.visitor, %{
                 origin: %{type: "place", neighbourhood_id: ctx.kypseli.id}
               })

      assert %{"origin" => %{"type" => "place", "latitude" => 38.001, "longitude" => 23.735}} =
               search(ctx, ctx.visitor, %{origin: %{type: "place", query: "Φωκίωνος Νέγρη 12"}})

      search(
        ctx,
        ctx.visitor,
        %{origin: %{type: "place", neighbourhood_id: Ecto.UUID.generate()}},
        422
      )

      search(ctx, ctx.visitor, %{origin: %{type: "place", query: "Πουθενά"}}, 422)

      search(ctx, ctx.visitor, %{filter: %{radius_km: 2.0}})

      assert %{"last_used" => %{"radius_km" => 2.0, "v" => 1}} =
               ctx.as.(ctx.visitor) |> get("/api/me/filters/around_me") |> json_response(200)
    end

    test "Γύρω μου needs a signed-in person", ctx do
      _ = ctx

      build_conn()
      |> send_json(:post, "/api/around/search", %{origin: @here})
      |> json_response(401)
    end
  end

  # -------------------------------------------------------------- alerts

  describe "saved-filter alerts" do
    test "at most one a day, only for what is new, and only for named filters", ctx do
      conn = ctx.as.(ctx.visitor)

      conn
      |> send_json(:put, "/api/me/around/area", %{neighbourhood_ids: [ctx.kypseli.id]})
      |> json_response(200)

      %{"saved" => [%{"id" => id, "alert" => false}]} =
        conn
        |> send_json(:post, "/api/me/filters/around_me", %{
          name: "Κοντά",
          params: %{kinds: ["events"]}
        })
        |> json_response(200)

      event(ctx.alpha, %{
        title: "Before the alert",
        inserted_at: DateTime.add(DateTime.utc_now(), -3600, :second)
      })

      assert %{"saved" => [%{"alert" => true}]} =
               conn
               |> send_json(:put, "/api/me/filters/around_me/#{id}/alert", %{enabled: true})
               |> json_response(200)

      conn
      |> send_json(:put, "/api/me/filters/feed/#{id}/alert", %{enabled: true})
      |> json_response(422)

      ctx.as.(user_fixture())
      |> send_json(:put, "/api/me/filters/around_me/#{id}/alert", %{enabled: true})
      |> json_response(404)

      now = DateTime.utc_now()

      alerts = fn ->
        Repo.all(
          from n in Notification,
            where: n.user_id == ^ctx.visitor.id and n.type == :around_new_matches
        )
      end

      run = fn at ->
        AroundAlerts.call(at)
        Oban.drain_queue(queue: :notifications, with_safety: false)
      end

      # Nothing new since the alert was turned on: nothing sent.
      run.(DateTime.add(now, 60, :second))
      assert alerts.() == []

      # A new event the next day: one alert, however often the sweep runs.
      tomorrow = DateTime.add(now, 1, :day)

      event(ctx.alpha, %{
        title: "New",
        inserted_at: DateTime.add(now, 120, :second),
        starts_at: DateTime.add(now, 3, :day)
      })

      event(ctx.far, %{title: "New but far", inserted_at: DateTime.add(now, 120, :second)})
      run.(tomorrow)
      run.(DateTime.add(tomorrow, 60, :second))
      assert [alert] = alerts.()
      assert alert.payload["count"] == 1
      assert alert.payload["url"] == "/around?filter=#{id}"

      # The day after, nothing new: still one.
      run.(DateTime.add(now, 2, :day))
      assert length(alerts.()) == 1

      # Turned off: no more.
      conn
      |> send_json(:put, "/api/me/filters/around_me/#{id}/alert", %{enabled: false})
      |> json_response(200)

      event(ctx.alpha, %{
        title: "Later",
        inserted_at: DateTime.add(now, 3, :day),
        starts_at: DateTime.add(now, 5, :day)
      })

      run.(DateTime.add(now, 4, :day))
      assert length(alerts.()) == 1
    end
  end
end
