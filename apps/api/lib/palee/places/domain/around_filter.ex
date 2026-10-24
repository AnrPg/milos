defmodule Palee.Places.Domain.AroundFilter do
  @moduledoc """
  The Γύρω μου filter (ADR-154, vision §7.2), modelled once and versioned:
  the search endpoints, the remembered last-used filter and named saved
  filters («ΣΚ κοντά») all go through `parse/2` and store `to_params/1`.

  * **Πού:** `radius_km` (0.5–50, default 3) and optional
    `neighbourhood_ids` (gazetteer ids, at most 5): when given, the search
    starts from their centroids.
  * **Τι:** `kinds` among `events boxes clubs posts` (default the first
    three; posts only when asked for).
  * **Είδος / Για / Γλώσσα / Παροχές:** `disciplines`, `audiences`,
    `languages` and `amenities` from the box-profile vocabularies
    (ADR-142). Accessibility is the amenities `wheelchair_accessible` and
    `accessible_restroom`.
  * **Επίπεδο:** `levels` among the class levels (`beginner all_levels
    advanced`, ADR-197): a host matches when it runs a current class type
    at one of them; like the tags, a person's post has no host and drops out.
  * **Πότε:** `when` (`today tomorrow weekend week range`, with `date_from`
    and `date_to` for a range of at most 62 days) and `times`
    (`morning midday evening`); they narrow events only.
  * **Κόστος:** `cost` (`free`, `trial`) and a price range,
    `min_price_cents` and `max_price_cents` (either end open, min ≤ max);
    the range narrows events only.

  Unknown keys are ignored, so an older client's saved filter still parses;
  a filter from a newer version (`v` above 1) is refused rather than
  half-understood.
  """

  @version 1
  @kinds ~w(events boxes clubs posts)
  @default_kinds ~w(events boxes clubs)
  @whens ~w(today tomorrow weekend week range)
  @times ~w(morning midday evening)
  @costs ~w(free trial)
  @default_radius_km 3.0
  @min_radius_km 0.5
  @max_radius_km 50.0
  @max_neighbourhoods 5
  @max_tags 10
  @max_range_days 62
  @max_price_cents 1_000_000
  @uuid ~r/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/
  @language ~r/^[a-z]{2}$/

  @type t :: %__MODULE__{}

  defstruct version: @version,
            radius_km: @default_radius_km,
            neighbourhood_ids: [],
            kinds: @default_kinds,
            disciplines: [],
            when: nil,
            date_from: nil,
            date_to: nil,
            times: [],
            cost: [],
            min_price_cents: nil,
            max_price_cents: nil,
            audiences: [],
            languages: [],
            amenities: [],
            levels: []

  def version, do: @version
  def kinds, do: @kinds
  def default_kinds, do: @default_kinds
  def whens, do: @whens
  def times, do: @times
  def costs, do: @costs
  def max_radius_km, do: @max_radius_km
  def min_radius_km, do: @min_radius_km
  def default_radius_km, do: @default_radius_km
  def max_neighbourhoods, do: @max_neighbourhoods

  @doc "The filter with nothing chosen."
  def default, do: %__MODULE__{}

  @doc """
  Parses and normalises filter params (string or atom keys). `vocabulary`
  holds the allowed `disciplines`, `audiences`, `amenities` and `levels`. Errors are
  `{:error, [{field, message}]}`.
  """
  def parse(params, vocabulary) when is_map(params) do
    params = Map.new(params, fn {key, value} -> {to_string(key), value} end)

    with :ok <- check_version(params["v"]),
         {:ok, radius_km} <- radius(params["radius_km"]),
         {:ok, neighbourhood_ids} <- uuids(params["neighbourhood_ids"]),
         {:ok, kinds} <- kinds(params["kinds"]),
         {:ok, disciplines} <- tags(:disciplines, params["disciplines"], vocabulary),
         {:ok, audiences} <- tags(:audiences, params["audiences"], vocabulary),
         {:ok, amenities} <- tags(:amenities, params["amenities"], vocabulary),
         {:ok, levels} <- tags(:levels, params["levels"], vocabulary),
         {:ok, languages} <- languages(params["languages"]),
         {:ok, {when_, date_from, date_to}} <-
           when_(params["when"], params["date_from"], params["date_to"]),
         {:ok, times} <- subset(:times, params["times"], @times),
         {:ok, cost} <- subset(:cost, params["cost"], @costs),
         {:ok, {min_price_cents, max_price_cents}} <-
           price_range(params["min_price_cents"], params["max_price_cents"]) do
      {:ok,
       %__MODULE__{
         radius_km: radius_km,
         neighbourhood_ids: neighbourhood_ids,
         kinds: kinds,
         disciplines: disciplines,
         audiences: audiences,
         amenities: amenities,
         levels: levels,
         languages: languages,
         when: when_,
         date_from: date_from,
         date_to: date_to,
         times: times,
         cost: cost,
         min_price_cents: min_price_cents,
         max_price_cents: max_price_cents
       }}
    end
  end

  def parse(nil, vocabulary), do: parse(%{}, vocabulary)
  def parse(_params, _vocabulary), do: {:error, [filter: "must be an object"]}

  @doc "The canonical JSON form, what saved filters store and the API echoes."
  def to_params(%__MODULE__{} = filter) do
    %{
      "v" => filter.version,
      "radius_km" => filter.radius_km,
      "neighbourhood_ids" => filter.neighbourhood_ids,
      "kinds" => filter.kinds,
      "disciplines" => filter.disciplines,
      "when" => filter.when,
      "date_from" => filter.date_from && Date.to_iso8601(filter.date_from),
      "date_to" => filter.date_to && Date.to_iso8601(filter.date_to),
      "times" => filter.times,
      "cost" => filter.cost,
      "min_price_cents" => filter.min_price_cents,
      "max_price_cents" => filter.max_price_cents,
      "audiences" => filter.audiences,
      "languages" => filter.languages,
      "amenities" => filter.amenities,
      "levels" => filter.levels
    }
  end

  @doc """
  How many facets differ from the default, for «Φίλτρα (n)»: where (a radius
  other than the default, or neighbourhoods), what, discipline, when, cost,
  audience, language, amenities and level each count once.
  """
  def active_count(%__MODULE__{} = filter) do
    [
      filter.neighbourhood_ids != [] or filter.radius_km != @default_radius_km,
      filter.kinds != @default_kinds,
      filter.disciplines != [],
      not is_nil(filter.when) or filter.times != [],
      filter.cost != [] or price_range?(filter),
      filter.audiences != [],
      filter.languages != [],
      filter.amenities != [],
      filter.levels != []
    ]
    |> Enum.count(& &1)
  end

  @doc "Whether the filter narrows by a price range (either end)."
  def price_range?(%__MODULE__{min_price_cents: min, max_price_cents: max}),
    do: not is_nil(min) or not is_nil(max)

  # ------------------------------------------------------------------ fields

  defp check_version(nil), do: :ok
  defp check_version(@version), do: :ok
  defp check_version(_other), do: {:error, [v: "is not a supported filter version"]}

  defp radius(nil), do: {:ok, @default_radius_km}

  defp radius(value) when is_number(value) do
    if value >= @min_radius_km and value <= @max_radius_km,
      do: {:ok, Float.round(value * 1.0, 1)},
      else: {:error, [radius_km: "must be between #{@min_radius_km} and #{@max_radius_km}"]}
  end

  defp radius(_value), do: {:error, [radius_km: "must be a number"]}

  defp uuids(nil), do: {:ok, []}

  defp uuids(ids) when is_list(ids) do
    ids = ids |> Enum.map(&normalize_id/1) |> Enum.uniq()

    cond do
      Enum.any?(ids, &is_nil/1) -> {:error, [neighbourhood_ids: "must be ids"]}
      length(ids) > @max_neighbourhoods -> {:error, [neighbourhood_ids: "at most 5"]}
      true -> {:ok, ids}
    end
  end

  defp uuids(_ids), do: {:error, [neighbourhood_ids: "must be a list"]}

  defp normalize_id(id) when is_binary(id) do
    id = String.downcase(id)
    if id =~ @uuid, do: id
  end

  defp normalize_id(_id), do: nil

  defp kinds(nil), do: {:ok, @default_kinds}

  defp kinds(kinds) do
    case subset(:kinds, kinds, @kinds) do
      {:ok, []} -> {:error, [kinds: "pick at least one"]}
      other -> other
    end
  end

  defp tags(_field, nil, _vocabulary), do: {:ok, []}

  defp tags(field, values, vocabulary) do
    with {:ok, values} <- subset(field, values, Map.fetch!(vocabulary, field)) do
      if length(values) > @max_tags,
        do: {:error, [{field, "at most #{@max_tags}"}]},
        else: {:ok, values}
    end
  end

  defp languages(nil), do: {:ok, []}

  defp languages(values) when is_list(values) do
    values = values |> Enum.map(&language/1) |> Enum.uniq()

    cond do
      Enum.any?(values, &is_nil/1) -> {:error, [languages: "must be ISO 639-1 codes"]}
      length(values) > @max_tags -> {:error, [languages: "at most #{@max_tags}"]}
      true -> {:ok, Enum.sort(values)}
    end
  end

  defp languages(_values), do: {:error, [languages: "must be a list"]}

  defp language(value) when is_binary(value) do
    value = value |> String.trim() |> String.downcase()
    if value =~ @language, do: value
  end

  defp language(_value), do: nil

  # A subset of `allowed`, unique, in the allowed list's order.
  defp subset(_field, nil, _allowed), do: {:ok, []}

  defp subset(field, values, allowed) when is_list(values) do
    if Enum.all?(values, &(is_binary(&1) and &1 in allowed)),
      do: {:ok, Enum.filter(allowed, &(&1 in values))},
      else: {:error, [{field, "has an unknown value"}]}
  end

  defp subset(field, _values, _allowed), do: {:error, [{field, "must be a list"}]}

  defp when_(nil, _from, _to), do: {:ok, {nil, nil, nil}}

  defp when_("range", from, to) do
    with {:ok, from} <- date(:date_from, from),
         {:ok, to} <- date(:date_to, to) do
      diff = Date.diff(to, from)

      cond do
        diff < 0 -> {:error, [date_to: "must not be before date_from"]}
        diff >= @max_range_days -> {:error, [date_to: "at most #{@max_range_days} days"]}
        true -> {:ok, {"range", from, to}}
      end
    end
  end

  defp when_(value, _from, _to) when value in @whens, do: {:ok, {value, nil, nil}}
  defp when_(_value, _from, _to), do: {:error, [when: "has an unknown value"]}

  defp date(field, value) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> {:ok, date}
      _invalid -> {:error, [{field, "must be a date (YYYY-MM-DD)"}]}
    end
  end

  defp date(field, _value), do: {:error, [{field, "must be a date (YYYY-MM-DD)"}]}

  # A minimum of 0 is no minimum, so «€0–€30» and «up to €30» are one filter.
  defp price_range(min, max) do
    with {:ok, min} <- price(:min_price_cents, min),
         {:ok, max} <- price(:max_price_cents, max) do
      cond do
        is_integer(min) and is_integer(max) and min > max ->
          {:error, [min_price_cents: "must not be above max_price_cents"]}

        min == 0 ->
          {:ok, {nil, max}}

        true ->
          {:ok, {min, max}}
      end
    end
  end

  defp price(_field, nil), do: {:ok, nil}

  defp price(_field, value) when is_integer(value) and value >= 0 and value <= @max_price_cents,
    do: {:ok, value}

  defp price(field, _value), do: {:error, [{field, "must be a whole number of cents"}]}
end
