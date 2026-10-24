defmodule Palee.Infrastructure.Places.EctoDiscoveryStore do
  @moduledoc """
  Discovery through the `palee_around_*` SECURITY DEFINER functions
  (ADR-154, migration `20261024100000_around_me`; the price range since
  `20261214100000_around_price_range`, the level since `20261218100000_around_level`). The origin goes in as a
  geography multipoint and the search area's bounding box as an envelope,
  so the spatial predicates in the functions use the GiST indexes.
  """

  @behaviour Palee.Places.Ports.DiscoveryStore

  alias Palee.Repo

  @area "ST_GeogFromText($1), $2::float8, ST_MakeEnvelope($3::float8, $4::float8, $5::float8, $6::float8, 4326)::geography"

  @impl true
  def search(_context, "events", area, plan, cursor, limit) do
    {from, to} = windows(plan.windows)

    """
    SELECT id, organization_id, latitude, longitude, distance_m, starts_at, total
    FROM palee_around_events(#{@area}, $7::timestamptz, $8::timestamptz[], $9::timestamptz[],
      $10::integer, $11::integer, $12::text[], $13::text[], $14::text[], $15::text[], $16::text[],
      $17::timestamptz, $18::timestamptz, $19::uuid, $20::integer)
    """
    |> query(
      area_params(area) ++
        [
          plan.now,
          from,
          to,
          plan.max_price_cents,
          plan.min_price_cents,
          plan.disciplines,
          plan.audiences,
          plan.languages,
          plan.amenities,
          plan.levels,
          plan.created_after,
          cursor && cursor.at,
          cursor && uuid(cursor.id),
          limit
        ]
    )
    |> page(fn [id, organization_id, latitude, longitude, distance, starts_at, total] ->
      {%{
         id: load(id),
         organization_id: load(organization_id),
         latitude: latitude,
         longitude: longitude,
         distance_m: distance,
         starts_at: starts_at
       }, total}
    end)
  end

  def search(_context, "boxes", area, plan, cursor, limit) do
    """
    SELECT organization_id, location_id, latitude, longitude, distance_m, neighbourhood, city,
           takes_trials, snapshot, slug, title, logo_url, primary_color, rank, total
    FROM palee_around_boxes(#{@area}, $7::boolean, $8::uuid[], $9::text[], $10::text[], $11::text[], $12::text[],
      $13::text[], $14::timestamptz, $15::integer, $16::float8, $17::uuid, $18::integer)
    """
    |> query(
      area_params(area) ++
        [
          plan.trial_only,
          uuids(plan.exclude_ids),
          plan.disciplines,
          plan.audiences,
          plan.languages,
          plan.amenities,
          plan.levels,
          plan.created_after,
          cursor && cursor.rank,
          cursor && cursor.distance_m,
          cursor && uuid(cursor.id),
          limit
        ]
    )
    |> page(fn [
                 organization_id,
                 location_id,
                 latitude,
                 longitude,
                 distance,
                 neighbourhood,
                 city,
                 takes_trials,
                 snapshot,
                 slug,
                 title,
                 logo_url,
                 primary_color,
                 rank,
                 total
               ] ->
      {%{
         organization_id: load(organization_id),
         location_id: load(location_id),
         latitude: latitude,
         longitude: longitude,
         distance_m: distance,
         neighbourhood: neighbourhood,
         city: city,
         takes_trials: takes_trials,
         snapshot: snapshot || %{},
         slug: slug,
         name: title,
         logo_url: logo_url,
         primary_color: primary_color,
         rank: rank
       }, total}
    end)
  end

  def search(_context, "clubs", area, plan, cursor, limit) do
    """
    SELECT id, organization_id, latitude, longitude, distance_m, total
    FROM palee_around_clubs(#{@area}, $7::text[], $8::text[], $9::text[], $10::text[], $11::text[],
      $12::timestamptz, $13::float8, $14::uuid, $15::integer)
    """
    |> query(
      area_params(area) ++
        [
          plan.disciplines,
          plan.audiences,
          plan.languages,
          plan.amenities,
          plan.levels,
          plan.created_after,
          cursor && cursor.distance_m,
          cursor && uuid(cursor.id),
          limit
        ]
    )
    |> page(fn [id, organization_id, latitude, longitude, distance, total] ->
      {%{
         id: load(id),
         organization_id: load(organization_id),
         latitude: latitude,
         longitude: longitude,
         distance_m: distance
       }, total}
    end)
  end

  def search(_context, "posts", area, plan, cursor, limit) do
    """
    SELECT id, source, organization_id, author_id, latitude, longitude, distance_m,
           created_at, total
    FROM palee_around_posts(#{@area}, $7::timestamptz, $8::uuid, $9::text[], $10::text[], $11::text[], $12::text[],
      $13::text[], $14::timestamptz, $15::timestamptz, $16::uuid, $17::integer)
    """
    |> query(
      area_params(area) ++
        [
          plan.since,
          uuid(plan.viewer_id),
          plan.disciplines,
          plan.audiences,
          plan.languages,
          plan.amenities,
          plan.levels,
          plan.created_after,
          cursor && cursor.at,
          cursor && uuid(cursor.id),
          limit
        ]
    )
    |> page(fn [id, source, organization_id, author_id, lat, lng, distance, created_at, total] ->
      {%{
         id: load(id),
         source: source,
         organization_id: load(organization_id),
         author_id: load(author_id),
         latitude: lat,
         longitude: lng,
         distance_m: distance,
         created_at: created_at
       }, total}
    end)
  end

  @impl true
  def counts(_context, _area, %{kinds: []}, _radii), do: %{}

  def counts(_context, area, plan, radii_m) do
    {from, to} = windows(plan.windows)
    max_radius = Enum.max(radii_m)
    {west, south, east, north} = area.bbox

    """
    SELECT kind, radius_m, total
    FROM palee_around_counts(
      ST_GeogFromText($1), $2::float8[], $3::float8,
      ST_MakeEnvelope($4::float8, $5::float8, $6::float8, $7::float8, 4326)::geography,
      $8::text[], $9::timestamptz, $10::timestamptz[], $11::timestamptz[], $12::integer, $13::integer,
      $14::boolean, $15::uuid[], $16::timestamptz, $17::uuid, $18::text[], $19::text[], $20::text[], $21::text[],
      $22::text[], $23::timestamptz)
    """
    |> query([
      multipoint(area.points),
      Enum.map(radii_m, &(&1 * 1.0)),
      max_radius * 1.0,
      west,
      south,
      east,
      north,
      plan.kinds,
      plan.now,
      from,
      to,
      plan.max_price_cents,
      plan.min_price_cents,
      plan.trial_only,
      uuids(plan.exclude_ids),
      plan.since,
      uuid(plan.viewer_id),
      plan.disciplines,
      plan.audiences,
      plan.languages,
      plan.amenities,
      plan.levels,
      plan.created_after
    ])
    |> Enum.reduce(%{}, fn [kind, radius, total], acc ->
      Map.update(acc, kind, %{radius => total}, &Map.put(&1, radius, total))
    end)
  end

  @impl true
  def pins(_context, _area, %{kinds: []}, _limit), do: []

  def pins(_context, area, plan, limit) do
    {from, to} = windows(plan.windows)

    """
    SELECT kind, id, latitude, longitude, title, slug, distance_m
    FROM palee_around_pins(#{@area}, $7::text[], $8::timestamptz, $9::timestamptz[],
      $10::timestamptz[], $11::integer, $12::integer, $13::boolean, $14::uuid[], $15::timestamptz,
      $16::uuid, $17::text[], $18::text[], $19::text[], $20::text[], $21::text[], $22::integer)
    """
    |> query(
      area_params(area) ++
        [
          plan.kinds,
          plan.now,
          from,
          to,
          plan.max_price_cents,
          plan.min_price_cents,
          plan.trial_only,
          uuids(plan.exclude_ids),
          plan.since,
          uuid(plan.viewer_id),
          plan.disciplines,
          plan.audiences,
          plan.languages,
          plan.amenities,
          plan.levels,
          limit
        ]
    )
    |> Enum.map(fn [kind, id, latitude, longitude, title, slug, distance] ->
      %{
        kind: kind,
        id: load(id),
        latitude: latitude,
        longitude: longitude,
        title: title,
        slug: slug,
        distance_m: distance
      }
    end)
  end

  @impl true
  def people_within(_context, user_ids, radius_m) do
    "SELECT palee_partner_people_within($1::uuid[], $2::float8)"
    |> query([uuids(user_ids), radius_m * 1.0])
    |> Enum.map(fn [id] -> load(id) end)
  end

  defp query(sql, params), do: Repo.query!(sql, params).rows

  defp page(rows, fun) do
    pairs = Enum.map(rows, fun)

    total =
      case pairs do
        [{_row, total} | _rest] -> total
        [] -> 0
      end

    {Enum.map(pairs, &elem(&1, 0)), total}
  end

  defp area_params(%{points: points, radius_m: radius, bbox: {west, south, east, north}}),
    do: [multipoint(points), radius * 1.0, west, south, east, north]

  defp multipoint(points) do
    inner = Enum.map_join(points, ",", fn {lat, lng} -> "(#{lng * 1.0} #{lat * 1.0})" end)
    "SRID=4326;MULTIPOINT(#{inner})"
  end

  defp windows(nil), do: {nil, nil}

  defp windows(windows),
    do: {Enum.map(windows, &elem(&1, 0)), Enum.map(windows, &elem(&1, 1))}

  defp uuids(ids), do: Enum.flat_map(ids || [], &List.wrap(uuid(&1)))

  defp uuid(nil), do: nil

  defp uuid(id) do
    case Ecto.UUID.dump(id) do
      {:ok, binary} -> binary
      :error -> nil
    end
  end

  defp load(nil), do: nil
  defp load(binary), do: Ecto.UUID.load!(binary)
end
