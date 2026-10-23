defmodule Palee.Places.Domain.GeonamesPlace do
  @moduledoc """
  GeoNames towns as gazetteer places (ADR-188). Pure rules over the
  tab-separated `cities500` dump: which rows are places people search for,
  their Greek and English names, the names they are found by, how far they
  reach, and which curated places they would only duplicate.

  Columns of a row: geonameid, name, asciiname, alternatenames, latitude,
  longitude, feature class, feature code, country code, cc2, admin1, admin2,
  admin3, admin4, population, elevation, dem, timezone, modification date.
  """

  alias Palee.Places.Domain.{SearchKey, WorldPlace}

  # Abandoned, destroyed or historical places are not where anyone trains.
  @skipped_codes ~w(PPLH PPLQ PPLW PPLCH)
  @neighbourhood_codes ~w(PPLX)
  # Alternate names kept for search: enough for spellings, not every language.
  @max_search_names 12
  @min_radius_m 1_000
  @max_radius_m 30_000

  @doc """
  One dump line as a place, or nil. `admin1` maps "GR.ESYE31" to a region
  name, `countries` maps "GR" to a country name.
  """
  def from_line(line, admin1, countries) when is_binary(line) do
    case String.split(line, "\t") do
      [id, name, ascii, alternates, lat, lng, "P", code, country, _cc2, admin | rest]
      when code not in @skipped_codes ->
        build(%{
          id: id,
          name: name,
          ascii: ascii,
          alternates: split_alternates(alternates),
          latitude: parse_float(lat),
          longitude: parse_float(lng),
          code: code,
          country: country,
          region: Map.get(admin1, country <> "." <> admin),
          country_name: Map.get(countries, country),
          population: rest |> Enum.at(3) |> parse_integer()
        })

      _other ->
        nil
    end
  end

  defp build(%{latitude: lat, longitude: lng} = row)
       when is_float(lat) and is_float(lng) and byte_size(row.country) == 2 do
    greek = Enum.find(row.alternates, &greek?/1)
    context = join([row.region, row.country_name])

    %{
      slug: "gn-" <> row.id,
      kind: if(row.code in @neighbourhood_codes, do: "neighbourhood", else: "city"),
      name: greek || row.name,
      name_en: row.name,
      context: context,
      context_en: context,
      country_code: row.country,
      latitude: lat,
      longitude: lng,
      radius_m: radius(row.population),
      population: row.population,
      search_key: search_key([row.name, row.ascii, greek | row.alternates], context)
    }
    |> then(&Map.merge(&1, %{id: WorldPlace.id(&1.slug), name_key: WorldPlace.name_key(&1)}))
  end

  defp build(_row), do: nil

  @doc "How far a town reaches, roughly, from its population."
  def radius(population) when is_integer(population) and population > 0,
    do: (:math.sqrt(population) * 25) |> round() |> max(@min_radius_m) |> min(@max_radius_m)

  def radius(_population), do: @min_radius_m * 2

  @doc "Whether a place only repeats a curated (or otherwise known) place nearby."
  def duplicate?(place, known) do
    Enum.any?(
      known,
      &(&1[:country_code] == place.country_code and WorldPlace.same_place?(&1, place))
    )
  end

  @doc "admin1CodesASCII.txt lines → %{\"GR.ESYE31\" => \"Attica\"}."
  def admin1_names(lines) do
    for line <- lines,
        [code, name | _rest] <- [String.split(line, "\t")],
        into: %{},
        do: {code, name}
  end

  @doc "countryInfo.txt lines (comments skipped) → %{\"GR\" => \"Greece\"}."
  def country_names(lines) do
    for line <- lines,
        not String.starts_with?(line, "#"),
        [iso, _iso3, _num, _fips, name | _rest] <- [String.split(line, "\t")],
        into: %{},
        do: {iso, name}
  end

  # Latin and Greek spellings only: the ones people type here.
  defp search_key(names, context) do
    names
    |> Enum.filter(&(is_binary(&1) and &1 != "" and searchable?(&1)))
    |> Enum.map(&SearchKey.normalize/1)
    |> Enum.uniq()
    |> Enum.take(@max_search_names)
    |> Kernel.++([SearchKey.normalize(context || "")])
    |> Enum.reject(&(&1 == ""))
    |> Enum.join(" ")
  end

  defp searchable?(name), do: String.match?(name, ~r/^[\p{Latin}\p{Greek}\p{Mn}0-9 '’.\-()]+$/u)

  defp greek?(name),
    do: String.match?(name, ~r/\p{Greek}/u) and not String.match?(name, ~r/\p{Latin}/u)

  defp split_alternates(""), do: []
  defp split_alternates(text), do: String.split(text, ",")

  defp parse_float(text) do
    case Float.parse(text) do
      {value, ""} -> value
      _invalid -> nil
    end
  end

  defp parse_integer(nil), do: nil

  defp parse_integer(text) do
    case Integer.parse(text) do
      {value, ""} -> value
      _invalid -> nil
    end
  end

  defp join(parts) do
    case Enum.filter(parts, &(is_binary(&1) and &1 != "")) do
      [] -> nil
      kept -> Enum.join(kept, ", ")
    end
  end
end
