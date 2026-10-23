defmodule Palee.Application.EventPresenter do
  @moduledoc """
  Club events as the member app and «Κοινότητα» show them (ADR-153): when
  and where, places, price, the club and box it belongs to, and where the
  viewer stands («Θα έρθω», waitlist, guest, paid). Who's going shows by
  name only to the event's audience (the club, or the member group for a
  group's event); everyone else gets the count.

  `viewer` is `%{user_id, club_ids, manage_organization_ids, clubs}`:
  the clubs the viewer can see (ids and their `ClubScope` faces) and the
  boxes where they run events.

  ADR-185: every event also says who hosts it (`host`: a person for their
  own events, else the business), its accepted co-hosts and its audience;
  members of a co-host belong to its audience like the host's own.
  """

  alias Palee.Application.{BoxPhotoCovers, CommunityPeople}
  alias Palee.{Community, Facility, Organizations}

  @goers_preview 8

  def viewer(user_id, clubs, manage_organization_ids \\ []) do
    groups =
      clubs
      |> Enum.flat_map(&Map.get(&1, :channels, []))
      |> Enum.filter(&(&1.kind == "member_group"))

    %{
      user_id: user_id,
      club_ids: MapSet.new(clubs, & &1.id),
      clubs: Map.new(clubs, &{&1.id, &1}),
      groups: Map.new(groups, &{&1.id, &1}),
      group_ids: groups |> Enum.filter(& &1.participant) |> MapSet.new(& &1.id),
      admin_group_ids: groups |> Enum.filter(& &1.admin) |> MapSet.new(& &1.id),
      manage_organization_ids: MapSet.new(manage_organization_ids),
      cohosted_event_ids: cohosted_event_ids(user_id, clubs)
    }
  end

  # ADR-185: events co-hosted by the boxes whose club the viewer is in.
  defp cohosted_event_ids(user_id, clubs) do
    case clubs |> Enum.filter(&(&1.kind == "gym")) |> Enum.map(& &1.organization_id) do
      [] ->
        MapSet.new()

      ids ->
        %{user_id: user_id}
        |> Community.accepted_event_cohosts(nil, Enum.uniq(ids))
        |> MapSet.new(& &1.event_id)
    end
  end

  @doc """
  Whether the viewer is in the event's audience: its club (or a co-host's),
  or its group for a group-only event.
  """
  def belongs?(event, viewer) do
    Community.event_belongs?(event, %{
      club_member?: MapSet.member?(viewer.club_ids, event.club_id),
      group_member?: MapSet.member?(viewer.group_ids, event.channel_id),
      cohost_member?:
        MapSet.member?(Map.get(viewer, :cohosted_event_ids, MapSet.new()), event.id)
    })
  end

  @doc "Whether the viewer may see the event at all (EventPolicy.visible?/2)."
  def visible?(event, viewer, facts \\ %{}) do
    Community.event_visible?(
      event,
      Map.merge(
        %{belongs?: belongs?(event, viewer), manager?: manages?(event, viewer)},
        facts
      )
    )
  end

  @doc "Whether the viewer runs the event: manage_events at its box, or its group's admin."
  def manages?(event, viewer) do
    Community.event_manage_check(
      %{
        manage_events?: MapSet.member?(viewer.manage_organization_ids, event.organization_id),
        group_admin?: MapSet.member?(viewer.admin_group_ids, event.channel_id)
      },
      event.channel_id
    ) == :ok
  end

  @doc "Events for `viewer`; `goers: :all` lists everyone going (the event page)."
  def present(events, viewer, opts \\ [])
  def present([], _viewer, _opts), do: []

  def present(events, viewer, opts) do
    now = Keyword.get(opts, :now, DateTime.utc_now())
    by_org = Enum.group_by(events, & &1.organization_id)
    gym = fn organization_id -> %{organization_id: organization_id, user_id: viewer.user_id} end

    counts =
      Enum.reduce(by_org, %{}, fn {org, list}, acc ->
        Map.merge(acc, Community.attendee_counts(gym.(org), Enum.map(list, & &1.id)))
      end)

    ids = MapSet.new(events, & &1.id)

    mine =
      by_org
      |> Map.keys()
      |> Enum.flat_map(
        &Community.attendances_of(gym.(&1), viewer.user_id, Community.attendee_statuses())
      )
      |> Enum.filter(&MapSet.member?(ids, &1.event_id))
      |> Map.new(&{&1.event_id, &1})

    goers = goers(by_org, viewer, gym, Keyword.get(opts, :goers, :preview))
    locations = locations(Map.keys(by_org))
    clubs = clubs(by_org, viewer)
    boxes = boxes(Map.keys(by_org), viewer)
    covers = BoxPhotoCovers.urls(events)
    zones = Organizations.timezone_statuses(Map.keys(by_org))
    hosts = hosts(events, by_org, boxes)
    cohosts = cohosts(events, viewer)

    Enum.map(events, fn event ->
      count = Map.get(counts, event.id, %{})
      going = Map.get(count, "going", 0)
      my = Map.get(mine, event.id)
      belongs? = belongs?(event, viewer)

      %{
        id: event.id,
        organization_id: event.organization_id,
        club_id: event.club_id,
        channel_id: event.channel_id,
        group: group(event, viewer),
        series_id: event.series_id,
        post_id: event.post_id,
        title: event.title,
        description: event.description,
        starts_at: event.starts_at,
        ends_at: event.ends_at,
        place: place(event, locations),
        time_zone: time_zone(event, zones),
        time_zone_confirmed: time_zone_confirmed?(event, zones),
        capacity: event.capacity,
        going_count: going,
        waitlist_count: Map.get(count, "waitlisted", 0),
        spots_left: Community.event_spots_left(event, going),
        price_cents: event.price_cents,
        currency: event.currency,
        open_to_non_members: event.open_to_non_members,
        audience: Community.event_audience(event),
        host: Map.fetch!(hosts, event.id),
        cohosts: Map.get(cohosts, event.id, []),
        guest_pass_allowed: event.guest_pass_allowed,
        guests_per_member: event.guests_per_member,
        good_for_friends: event.good_for_friends,
        cover_media_id: event.cover_media_id,
        cover_url: event.cover_media_id && Map.get(covers, event.cover_media_id),
        cancelled: not is_nil(event.cancelled_at),
        cancelled_at: event.cancelled_at,
        cancel_reason: event.cancel_reason,
        club: Map.get(clubs, event.club_id, %{id: event.club_id, name: nil, kind: nil}),
        box: Map.get(boxes, event.organization_id, %{name: nil, slug: nil, logo_url: nil}),
        my: my && present_mine(my),
        goers: if(Community.event_show_names?(belongs?), do: Map.get(goers, event.id, [])),
        can_rsvp: Community.event_can_rsvp?(event, belongs?, my && my.status, now),
        can_manage: manages?(event, viewer)
      }
    end)
  end

  # ADR-185: a person's own event shows the person; any other the business.
  defp hosts(events, by_org, boxes) do
    kinds = Organizations.provider_kinds(Map.keys(by_org))

    people =
      events
      |> Enum.filter(&Community.organiser?(Map.get(kinds, &1.organization_id)))
      |> Enum.map(& &1.created_by_id)
      |> CommunityPeople.by_ids()

    Map.new(events, fn event ->
      kind = Map.get(kinds, event.organization_id)

      host =
        if Community.organiser?(kind) do
          person = CommunityPeople.person(people, event.created_by_id)

          %{
            kind: "person",
            organization_id: event.organization_id,
            name: person.nickname,
            slug: nil,
            logo_url: person.avatar_url,
            person: person
          }
        else
          box = Map.get(boxes, event.organization_id, %{name: nil, slug: nil, logo_url: nil})

          %{
            kind: "business",
            organization_id: event.organization_id,
            name: box.name,
            slug: box.slug,
            logo_url: box.logo_url,
            person: nil
          }
        end

      {event.id, host}
    end)
  end

  # Accepted co-hosts, as their public box pages show them.
  defp cohosts(events, viewer) do
    rows = Community.accepted_event_cohosts(%{user_id: viewer.user_id}, Enum.map(events, & &1.id), nil)

    faces =
      case rows |> Enum.map(& &1.cohost_organization_id) |> Enum.uniq() do
        [] -> %{}
        ids -> ids |> Organizations.public_boxes() |> Map.new(&{&1.organization_id, &1})
      end

    rows
    |> Enum.flat_map(fn row ->
      case Map.get(faces, row.cohost_organization_id) do
        nil ->
          []

        box ->
          [
            {row.event_id,
             %{
               organization_id: box.organization_id,
               name: box.name,
               slug: box.slug,
               logo_url: box.logo_url
             }}
          ]
      end
    end)
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
  end

  defp time_zone(event, zones),
    do: Community.event_time_zone(event, zones[event.organization_id].timezone)

  defp time_zone_confirmed?(event, zones),
    do: is_binary(event.time_zone) or zones[event.organization_id].confirmed

  defp present_mine(attendee) do
    %{
      status: attendee.status,
      source: attendee.source,
      invited_by_id: attendee.invited_by_id,
      paid: not is_nil(attendee.paid_at),
      late_cancel: attendee.late_cancel
    }
  end

  defp group(%{channel_id: nil}, _viewer), do: nil

  defp group(%{channel_id: id}, viewer) do
    case Map.get(viewer.groups, id) do
      nil -> %{id: id, name: nil}
      channel -> %{id: id, name: channel.name}
    end
  end

  defp place(%{location_id: nil} = event, _locations) do
    %{
      location_id: nil,
      name: event.place_name,
      address: event.address,
      neighbourhood: nil,
      city: nil,
      latitude: event.latitude,
      longitude: event.longitude
    }
  end

  defp place(event, locations) do
    case Map.get(locations, event.location_id) do
      nil ->
        %{
          location_id: event.location_id,
          name: nil,
          address: nil,
          neighbourhood: nil,
          city: nil,
          latitude: nil,
          longitude: nil
        }

      location ->
        %{
          location_id: location.id,
          name: location.name,
          address: location.address,
          neighbourhood: Map.get(location, :neighbourhood),
          city: Map.get(location, :city),
          latitude: location.latitude,
          longitude: location.longitude
        }
    end
  end

  defp goers(by_org, viewer, gym, mode) do
    by_org
    |> Enum.flat_map(fn {org, list} ->
      visible = Enum.filter(list, &belongs?(&1, viewer))
      Community.list_attendees(gym.(org), Enum.map(visible, & &1.id), ["going"])
    end)
    |> Enum.group_by(& &1.event_id)
    |> then(fn grouped ->
      grouped =
        if mode == :all,
          do: grouped,
          else: Map.new(grouped, fn {id, rows} -> {id, Enum.take(rows, @goers_preview)} end)

      people = grouped |> Map.values() |> List.flatten() |> Enum.map(& &1.user_id)
      people = CommunityPeople.by_ids(people)

      Map.new(grouped, fn {id, rows} ->
        {id, Enum.map(rows, &CommunityPeople.person(people, &1.user_id))}
      end)
    end)
  end

  defp locations(organization_ids) do
    organization_ids
    |> Enum.flat_map(&Facility.list_locations(%{organization_id: &1}))
    |> Map.new(&{&1.id, &1})
  end

  defp clubs(by_org, viewer) do
    known =
      Map.new(viewer.clubs, fn {id, club} ->
        {id, %{id: id, name: club.name, kind: club.kind}}
      end)

    missing =
      by_org
      |> Enum.filter(fn {_org, list} ->
        Enum.any?(list, &(not Map.has_key?(known, &1.club_id)))
      end)
      |> Enum.flat_map(fn {org, _list} ->
        %{organization_id: org, user_id: viewer.user_id} |> Community.list_clubs([org])
      end)

    names = boxes(Enum.map(missing, & &1.organization_id), viewer)

    missing
    |> Map.new(fn club ->
      name = club.name || Map.get(names, club.organization_id, %{})[:name]
      {club.id, %{id: club.id, name: name, kind: club.kind}}
    end)
    |> Map.merge(known)
  end

  defp boxes([], _viewer), do: %{}

  defp boxes(organization_ids, viewer) do
    from_scope =
      viewer.clubs
      |> Map.values()
      |> Enum.filter(&(&1.kind == "gym"))
      |> Map.new(
        &{&1.organization_id,
         %{name: &1.organization_name, slug: &1.organization_slug, logo_url: &1.logo_url}}
      )

    missing = Enum.reject(Enum.uniq(organization_ids), &Map.has_key?(from_scope, &1))

    published =
      if missing == [],
        do: %{},
        else:
          missing
          |> Organizations.public_boxes()
          |> Map.new(
            &{&1.organization_id, %{name: &1.name, slug: &1.slug, logo_url: &1.logo_url}}
          )

    Map.merge(published, from_scope)
  end
end
