defmodule MilosTraining.Application.AroundMe do
  @moduledoc """
  Γύρω μου (ADR-154, vision §6–7.2): what is near a member, by kind.

  * `search/3`: every selected kind's top cards with their totals, the
    origin the search used, and, when little was found, how much there is
    at wider radii. Remembers the filter as the person's last-used one.
  * `kind/4`: one kind, cursor-paged («Δες όλα»).
  * `pins/3`: map pins inside a viewport («Ψάξε εδώ»), capped.

  Discovery across gyms runs through `Places` (definer functions that see
  only public items); the cards come from the same presenters as the rest
  of the app, read in the person's session or each gym's scope. Every card
  carries its distance to one decimal of a kilometre; a person's post sits
  at their neighbourhood's centroid, never closer.
  """

  alias MilosTraining.Application.{
    BoxPhotoCovers,
    CommunityEvents,
    ListBookablePlaces,
    OpenClubs,
    PostPresenter,
    PublicBox
  }

  alias MilosTraining.{Community, Facility, Identity, Organizations, Places}

  @surface "around_me"

  @doc "The filter vocabularies (ADR-142 lists)."
  def vocabulary,
    do: %{
      disciplines: Organizations.box_disciplines(),
      audiences: Organizations.box_audiences(),
      amenities: Organizations.box_amenities()
    }

  def search(%{user_id: user_id} = context, body, now \\ DateTime.utc_now()) do
    body = stringify(body)
    memberships = Organizations.list_memberships(user_id)

    with {:ok, filter} <- Places.parse_filter(body["filter"], vocabulary()),
         {:ok, origin} <- origin(context, body["origin"], filter) do
      plan = Places.plan(filter, viewer(user_id, memberships), now, :list)
      area = Places.circle(origin.points, filter.radius_km * 1000)
      limit = Places.section_limit(body["limit"])

      sections =
        Map.new(Places.kinds(), fn kind ->
          {kind, if(kind in plan.kinds, do: section(context, kind, area, plan, nil, limit))}
        end)

      total =
        sections |> Map.values() |> Enum.reject(&is_nil/1) |> Enum.map(& &1.total) |> Enum.sum()

      if body["remember"] != false, do: remember(context, filter, now)

      {:ok,
       %{
         origin: Places.present_origin(origin),
         filter: Places.filter_params(filter),
         active_filters: Places.active_filters(filter),
         sections: sections,
         wider: if(Places.thin?(total), do: wider(context, origin, filter, plan), else: [])
       }}
    end
  end

  def kind(%{user_id: user_id} = context, kind, body, now \\ DateTime.utc_now()) do
    body = stringify(body)

    with :ok <- known_kind(kind),
         {:ok, filter} <- Places.parse_filter(body["filter"], vocabulary()),
         {:ok, cursor} <- Places.decode_cursor(kind, body["cursor"]),
         {:ok, origin} <- origin(context, body["origin"], filter) do
      plan = Places.plan(filter, viewer(user_id), now, :list)
      area = Places.circle(origin.points, filter.radius_km * 1000)

      page =
        if kind in plan.kinds,
          do: section(context, kind, area, plan, cursor, Places.page_limit(body["limit"])),
          else: empty_section(kind, plan)

      {:ok, Map.merge(%{kind: kind, origin: Places.present_origin(origin)}, page)}
    end
  end

  def pins(%{user_id: user_id} = context, body, now \\ DateTime.utc_now()) do
    body = stringify(body)

    with {:ok, filter} <- Places.parse_filter(body["filter"], vocabulary()),
         {:ok, bbox} <- bbox(body["bbox"]),
         {:ok, area} <- viewport(bbox) do
      plan = Places.plan(filter, viewer(user_id), now, :pins)
      limit = Places.pins_limit()
      pins = Places.pins(context, area, plan, limit + 1)

      {:ok,
       %{
         pins:
           pins
           |> Enum.take(limit)
           |> Enum.map(&Map.take(&1, [:kind, :id, :latitude, :longitude, :title, :slug])),
         truncated: length(pins) > limit
       }}
    end
  end

  @doc """
  Where the person's searches start when nothing is chosen (saved area,
  else their box), for alerts and screens that only need the origin.
  """
  def default_origin(context, filter) do
    origin(context, nil, filter)
  end

  @doc "The gyms the person actively belongs to, as the plan needs them."
  def viewer(user_id, memberships \\ nil) do
    memberships = memberships || Organizations.list_memberships(user_id)
    %{user_id: user_id, organization_ids: Enum.map(memberships, & &1.organization.id)}
  end

  # ------------------------------------------------------------- sections

  defp section(context, kind, area, plan, cursor, limit) do
    {rows, total} = Places.search(context, kind, area, plan, cursor, limit + 1)
    {page, rest} = Enum.split(rows, limit)

    %{
      total: total,
      items: hydrate(context, kind, page, plan),
      next_cursor: if(rest != [] and page != [], do: Places.encode_cursor(kind, List.last(page)))
    }
    |> with_placement(kind, plan)
  end

  defp empty_section(kind, plan),
    do: with_placement(%{total: 0, items: [], next_cursor: nil}, kind, plan)

  defp with_placement(section, "boxes", plan),
    do: Map.put(section, :placement, plan.boxes_placement)

  defp with_placement(section, _kind, _plan), do: section

  defp wider(context, origin, filter, plan) do
    case Places.wider_radii_km(filter.radius_km) do
      [] ->
        []

      radii_km ->
        radii_m = Enum.map(radii_km, &(&1 * 1000))
        area = Places.circle(origin.points, Enum.max(radii_m))
        counts = Places.counts(context, area, plan, radii_m)

        Enum.map(radii_km, fn radius_km ->
          by_kind =
            Map.new(plan.kinds, fn kind ->
              {kind, counts |> Map.get(kind, %{}) |> Map.get(radius_km * 1000, 0)}
            end)

          %{radius_km: radius_km, total: by_kind |> Map.values() |> Enum.sum(), by_kind: by_kind}
        end)
    end
  end

  # --------------------------------------------------------------- cards

  defp hydrate(_context, _kind, [], _plan), do: []

  defp hydrate(context, "events", rows, plan) do
    events =
      rows
      |> Enum.group_by(& &1.organization_id, & &1.id)
      |> Enum.flat_map(fn {organization_id, ids} ->
        Community.list_events(%{organization_id: organization_id, user_id: context.user_id}, %{
          organization_ids: [organization_id],
          ids: ids
        })
      end)

    cards = context |> CommunityEvents.present_cards(events, plan.now) |> Map.new(&{&1.id, &1})
    place(rows, cards, :id, :event)
  end

  defp hydrate(_context, "boxes", rows, _plan) do
    covers =
      rows
      |> Enum.map(&%{organization_id: &1.organization_id, cover_media_id: cover_id(&1)})
      |> BoxPhotoCovers.urls()

    Enum.map(rows, fn row ->
      snapshot = row.snapshot
      cover = cover_id(row)

      %{
        distance_km: Places.distance_km(row.distance_m),
        box: %{
          organization_id: row.organization_id,
          slug: row.slug,
          name: row.name,
          logo_url: row.logo_url,
          primary_color: row.primary_color,
          cover_url: cover && Map.get(covers, cover),
          neighbourhood: row.neighbourhood,
          city: row.city,
          latitude: row.latitude,
          longitude: row.longitude,
          disciplines: snapshot["disciplines"] || [],
          audiences: snapshot["audiences"] || [],
          languages: snapshot["languages"] || [],
          amenities: snapshot["amenities"] || [],
          takes_trials: row.takes_trials
        }
      }
    end)
  end

  defp hydrate(context, "clubs", rows, _plan) do
    clubs = Community.list_clubs_by_ids(context, Enum.map(rows, & &1.id))
    cards = context |> OpenClubs.present_cards(clubs) |> Map.new(&{&1.id, &1})
    place(rows, cards, :id, :club)
  end

  defp hydrate(%{user_id: user_id} = context, "posts", rows, _plan) do
    {club_rows, person_rows} = Enum.split_with(rows, &(&1.source == "club"))
    organization_ids = club_rows |> Enum.map(& &1.organization_id) |> Enum.uniq()

    club_posts =
      if club_rows == [] do
        []
      else
        context
        |> Community.list_public_posts(organization_ids, user_id, %{
          ids: Enum.map(club_rows, & &1.id),
          limit: length(club_rows)
        })
        |> PostPresenter.public_box_posts(PublicBox.boxes(organization_ids))
      end

    person_posts =
      if person_rows == [] do
        []
      else
        context
        |> Community.list_profile_posts(%{
          author_ids: person_rows |> Enum.map(& &1.author_id) |> Enum.uniq(),
          ids: Enum.map(person_rows, & &1.id),
          viewer_id: user_id,
          limit: length(person_rows)
        })
        |> PostPresenter.profile_posts(user_id)
      end

    cards = Map.new(club_posts ++ person_posts, &{&1.id, &1})
    place(rows, cards, :id, :post)
  end

  # Cards in the search's order, each with its distance; a row whose card
  # the person may not see (it changed since) drops out.
  defp place(rows, cards, key, name) do
    Enum.flat_map(rows, fn row ->
      case Map.get(cards, Map.fetch!(row, key)) do
        nil -> []
        card -> [%{:distance_km => Places.distance_km(row.distance_m), name => card}]
      end
    end)
  end

  defp cover_id(%{snapshot: snapshot}), do: snapshot["cover_photo_id"]

  # -------------------------------------------------------------- origin

  defp origin(context, spec, filter) do
    with {:ok, request} <- Places.parse_origin(spec),
         {:ok, filter_places} <- known_places(filter.neighbourhood_ids),
         {:ok, requested} <- requested(request) do
      Places.resolve_origin(%{
        neighbourhoods: filter_places,
        requested: requested,
        area:
          if(filter_places == [] and not is_map(requested),
            do: Places.home_area(context),
            else: []
          ),
        home: fn -> home_origin(context.user_id) end
      })
    end
  end

  defp known_places([]), do: {:ok, []}

  defp known_places(ids) do
    places = Places.neighbourhoods(ids)

    if length(places) == length(ids),
      do: {:ok, places},
      else: {:error, [neighbourhood_ids: "has an unknown place"]}
  end

  defp requested(nil), do: {:ok, nil}
  defp requested(:area), do: {:ok, :area}

  defp requested({:point, latitude, longitude}) do
    label =
      case Places.nearest_neighbourhood({latitude, longitude}) do
        %{name: name} -> name
        nil -> nil
      end

    {:ok, Places.point_origin("point", {latitude, longitude}, label)}
  end

  defp requested({:neighbourhood, id}) do
    case Places.neighbourhoods([id]) do
      [place] -> {:ok, Places.places_origin("place", [place])}
      [] -> {:error, :place_not_found}
    end
  end

  # A typed place: the gazetteer first (no outside call), else the geocoder.
  # A geocoded point is kept to 3 decimals: it may be someone's address.
  defp requested({:query, query}) do
    case Places.search_neighbourhoods(query, 1) do
      [place] ->
        {:ok, Places.places_origin("place", [place])}

      [] ->
        with {:ok, results} <- Facility.search_addresses(query, limit: 1),
             [first | _rest] <- results,
             {:ok, point} <- Places.round_point(first.latitude, first.longitude) do
          {:ok, Places.point_origin("place", point, first.label)}
        else
          {:error, :geocoder_unavailable} = error -> error
          _none -> {:error, :place_not_found}
        end
    end
  end

  defp home_origin(user_id) do
    places = ListBookablePlaces.call(user_id)
    pinned = Enum.filter(places, &is_number(&1.latitude))

    case Enum.find(pinned, & &1.home) || List.first(pinned) do
      nil ->
        nil

      place ->
        Places.point_origin(
          "box",
          {place.latitude, place.longitude},
          place.neighbourhood || place.name
        )
    end
  end

  # ------------------------------------------------------------- helpers

  defp remember(context, filter, now) do
    Identity.put_last_used_filter(context, @surface, Places.filter_params(filter), now)
  end

  defp known_kind(kind) do
    if kind in Places.kinds(), do: :ok, else: {:error, :not_found}
  end

  defp bbox(%{} = bbox) do
    bbox = stringify(bbox)

    case {bbox["west"], bbox["south"], bbox["east"], bbox["north"]} do
      {w, s, e, n} when is_number(w) and is_number(s) and is_number(e) and is_number(n) ->
        {:ok, {w, s, e, n}}

      _invalid ->
        {:error, [bbox: "needs west, south, east and north"]}
    end
  end

  defp bbox(_bbox), do: {:error, [bbox: "needs west, south, east and north"]}

  defp viewport(bbox) do
    case Places.viewport(bbox) do
      {:ok, area} -> {:ok, area}
      {:error, :viewport_too_large} -> {:error, [bbox: "is too large; zoom in"]}
      {:error, _invalid} -> {:error, [bbox: "is invalid"]}
    end
  end

  defp stringify(nil), do: %{}

  defp stringify(%{} = map),
    do: Map.new(map, fn {key, value} -> {to_string(key), value} end)

  defp stringify(_other), do: %{}
end
