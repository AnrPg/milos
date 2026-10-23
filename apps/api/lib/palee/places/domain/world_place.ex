defmodule Palee.Places.Domain.WorldPlace do
  @moduledoc """
  Geocoder results as gazetteer places (ADR-188). Pure rules: which results
  can be an area, how far an area reaches, the stable slug and id a place
  gets before and after it is stored, and how an address becomes the area
  around it without the address itself ever being kept.

  A geocoder result here is the `Palee.Application.Ports.Geocoder` place
  map; the same place comes back once per language (local names, English).
  """

  alias Palee.Places.Domain.SearchKey

  # Photon's `type` of a result → our kind; streets and houses are addresses.
  @area_layers %{"city" => "city", "district" => "neighbourhood", "locality" => "neighbourhood"}
  @address_layers ~w(street house)

  # How far a place reaches when the geocoder gives no bounding box.
  @default_radius_m %{
    "city" => 8_000,
    "town" => 4_000,
    "municipality" => 6_000,
    "village" => 1_500,
    "hamlet" => 800,
    "borough" => 3_000,
    "suburb" => 1_500,
    "quarter" => 1_000,
    "neighbourhood" => 800,
    "city_block" => 300,
    "locality" => 1_000
  }
  @min_radius_m 300
  @max_radius_m 50_000

  # The area around an address the geocoder cannot place in a neighbourhood:
  # a ~1 km grid cell, so the stored centroid never points at the address.
  @fallback_decimals 2
  @fallback_radius_m 1_500

  # Same name within this distance: the stored or curated place wins.
  @duplicate_reach_m 5_000

  @namespace "6f1c5e3a-9a43-4c8e-8d3b-2b8a1f0d7c55"

  @type suggestion :: %{
          id: binary(),
          slug: String.t(),
          kind: String.t(),
          name: String.t(),
          name_en: String.t(),
          context: String.t() | nil,
          context_en: String.t() | nil,
          country_code: String.t(),
          latitude: float(),
          longitude: float(),
          radius_m: pos_integer()
        }

  def layers, do: Map.keys(@area_layers) ++ @address_layers
  def area_layers, do: Map.keys(@area_layers)

  @doc """
  Pairs each local-language result with its English twin (same OSM object)
  and turns the pair into a suggestion; results that cannot be an area or an
  address are dropped. Order follows the local results.
  """
  def suggestions(local, english) do
    english_by_ref = english |> Enum.filter(& &1[:osm_ref]) |> Map.new(&{&1.osm_ref, &1})

    local
    |> Enum.map(&suggestion(&1, Map.get(english_by_ref, &1[:osm_ref])))
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq_by(& &1.slug)
  end

  @doc "One result (and its English twin, if any) as a suggestion, or nil."
  def suggestion(result, english \\ nil)

  def suggestion(%{osm_ref: ref, country_code: country} = result, english)
      when is_binary(ref) and is_binary(country) do
    english = english || result

    case kind(result) do
      nil ->
        nil

      kind ->
        %{
          slug: slug(kind, ref),
          kind: kind,
          name: name(result, kind),
          name_en: name(english, kind) || name(result, kind),
          context: context(result, kind),
          context_en: context(english, kind),
          country_code: country,
          latitude: result.latitude,
          longitude: result.longitude,
          radius_m: radius(result)
        }
        |> with_area(result, english)
        |> with_id()
    end
  end

  def suggestion(_result, _english), do: nil

  @doc "Whether a suggestion only says where an address is (it must be resolved to an area)."
  def address?(%{kind: "address"}), do: true
  def address?(_place), do: false

  @doc """
  The area a resolved neighbourhood (or town) result gives for an address.
  The geocoder may find nothing near; then a grid cell around the address,
  named after its neighbourhood or city, stands in.
  """
  def area_for_address(address, local, english) do
    case local && suggestion(local, english) do
      %{kind: kind} = area when kind != "address" ->
        if covers?(area, address), do: area, else: fallback_area(address)

      _none ->
        fallback_area(address)
    end
  end

  # The nearest neighbourhood the geocoder knows may still be far away.
  defp covers?(area, address) do
    distance_m({area.latitude, area.longitude}, {address.latitude, address.longitude}) <=
      max(area.radius_m * 1.5, 3_000)
  end

  defp fallback_area(address) do
    latitude = Float.round(address.latitude, @fallback_decimals)
    longitude = Float.round(address.longitude, @fallback_decimals)
    area = address.area

    %{
      slug: "geo-#{coordinate(latitude)}-#{coordinate(longitude)}",
      kind: "neighbourhood",
      name: area.name || address.country_code,
      name_en: area.name_en || area.name || address.country_code,
      context: area.context,
      context_en: area.context_en,
      country_code: address.country_code,
      latitude: latitude,
      longitude: longitude,
      radius_m: @fallback_radius_m
    }
    |> with_id()
  end

  @doc """
  Drops suggestions the reader already sees: a stored place with the same
  slug, or a place with the same name nearby (curated names win).
  """
  def without_duplicates(suggestions, known) do
    known_slugs = MapSet.new(known, & &1.slug)

    Enum.reject(suggestions, fn suggestion ->
      MapSet.member?(known_slugs, suggestion.slug) or
        Enum.any?(known, &same_place?(&1, suggestion))
    end)
  end

  @doc "Same name (either language) within a few kilometres."
  def same_place?(known, suggestion) do
    names = MapSet.new([known.name, known.name_en], &SearchKey.normalize/1)

    (MapSet.member?(names, SearchKey.normalize(suggestion.name)) or
       MapSet.member?(names, SearchKey.normalize(suggestion.name_en))) and
      distance_m({known.latitude, known.longitude}, {suggestion.latitude, suggestion.longitude}) <
        @duplicate_reach_m
  end

  @doc "The search key a stored place is found by: names and context, folded."
  def search_key(place) do
    [place.name, place.name_en, place[:context], place[:context_en]]
    |> Enum.filter(&(is_binary(&1) and &1 != ""))
    |> Enum.map(&SearchKey.normalize/1)
    |> Enum.uniq()
    |> Enum.join(" ")
  end

  @doc "The place's own names, folded: ranks a town above places merely in it."
  def name_key(place) do
    [place.name, place.name_en]
    |> Enum.filter(&(is_binary(&1) and &1 != ""))
    |> Enum.map(&SearchKey.normalize/1)
    |> Enum.uniq()
    |> Enum.join(" ")
  end

  @doc "The id a place gets when stored: derived from its slug, so it is known before."
  def id(slug) when is_binary(slug) do
    <<a::48, _v::4, b::12, _r::2, c::62, _rest::binary>> =
      :crypto.hash(:sha, uuid_bytes(@namespace) <> slug)

    Ecto.UUID.load!(<<a::48, 5::4, b::12, 2::2, c::62>>)
  end

  defp with_id(place), do: Map.put(place, :id, id(place.slug))

  defp kind(%{layer: layer} = result) do
    cond do
      Map.has_key?(@area_layers, layer) and is_binary(result[:name]) -> @area_layers[layer]
      layer in @address_layers -> "address"
      true -> nil
    end
  end

  defp kind(_result), do: nil

  defp name(result, "address"), do: result[:address] || result[:label]
  defp name(result, _area), do: result[:name]

  # What an address's area is called if the geocoder finds no neighbourhood.
  defp with_area(%{kind: "address"} = place, result, english) do
    Map.put(place, :area, %{
      name: area_name(result),
      name_en: area_name(english) || area_name(result),
      context: area_context(result),
      context_en: area_context(english)
    })
  end

  defp with_area(place, _result, _english), do: place

  defp area_name(result),
    do:
      Enum.find(
        [result[:neighbourhood], result[:city], result[:state], result[:country]],
        &present?/1
      )

  defp area_context(result) do
    case result[:neighbourhood] do
      nil -> join([result[:country]])
      _neighbourhood -> join([result[:city], result[:country]])
    end
  end

  defp present?(value), do: is_binary(value) and value != ""

  defp slug("address", ref), do: "addr-" <> String.downcase(ref)
  defp slug(_kind, ref), do: "osm-" <> String.downcase(ref)

  defp context(result, "address"),
    do: join([result[:neighbourhood], result[:city], result[:country]])

  defp context(result, "city"), do: join([result[:state], result[:country]])

  defp context(result, _neighbourhood),
    do: join([result[:city] != result[:name] && result[:city], result[:country]])

  @doc "How far a place reaches: half its bounding box diagonal, else by its type."
  def radius(result) do
    case result[:extent] do
      [min_lng, max_lat, max_lng, min_lat] when is_number(min_lng) ->
        (distance_m({min_lat, min_lng}, {max_lat, max_lng}) / 2) |> round() |> clamp()

      _none ->
        Map.get(@default_radius_m, result[:osm_value], 1_500)
    end
  end

  defp clamp(metres), do: metres |> max(@min_radius_m) |> min(@max_radius_m)

  defp distance_m({lat1, lng1}, {lat2, lng2}) do
    rad = :math.pi() / 180
    dlat = (lat2 - lat1) * rad
    dlng = (lng2 - lng1) * rad

    a =
      :math.pow(:math.sin(dlat / 2), 2) +
        :math.cos(lat1 * rad) * :math.cos(lat2 * rad) * :math.pow(:math.sin(dlng / 2), 2)

    2 * 6_371_000 * :math.asin(:math.sqrt(min(a, 1.0)))
  end

  defp join(parts) do
    case parts |> Enum.filter(&(is_binary(&1) and &1 != "")) |> Enum.uniq() do
      [] -> nil
      kept -> Enum.join(kept, ", ")
    end
  end

  defp coordinate(value), do: :erlang.float_to_binary(value, decimals: @fallback_decimals)

  defp uuid_bytes(uuid), do: uuid |> String.replace("-", "") |> Base.decode16!(case: :lower)
end
