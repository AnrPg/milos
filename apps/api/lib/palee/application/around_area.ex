defmodule Palee.Application.AroundArea do
  @moduledoc """
  «Η περιοχή μου» (ADR-154): the neighbourhoods a member searches Γύρω μου
  from by default, private to them, picked from the gazetteer. The first
  one is the main neighbourhood: when the person opts in to «Φαίνομαι στο
  Γύρω μου», their public posts show at its centroid.
  """

  alias Palee.Application.SignedToken
  alias Palee.Places

  # ADR-188: the geocoder is asked only when the stored gazetteer (curated,
  # GeoNames towns, picked places) has few matches or the query looks like an
  # address, and only for 3+ letters; once per language, in parallel.
  @local_limit 20
  @remote_below 6
  @remote_min_chars 3
  @remote_limit 10
  @remote_timeout_ms 6_000
  @ref_salt "palee:place-ref:v1"
  @ref_max_age_s 86_400

  @doc """
  Places for a picker matching `query`: stored places first (cities first),
  then places and addresses anywhere from the geocoder, each with a signed
  `ref` that `import_place/1` turns into a stored place. `remote` says
  whether the geocoder answered ("ok"), was down ("unavailable") or was not
  needed ("skipped"); stored places are listed either way.
  """
  def neighbourhoods(query) when is_binary(query) do
    local = Places.search_neighbourhoods(query, @local_limit)
    {remote, status} = remote_suggestions(query, local)

    {:ok,
     %{
       neighbourhoods: Enum.map(local, &present/1) ++ Enum.map(remote, &present_suggestion/1),
       remote: status
     }}
  end

  def neighbourhoods(_query), do: {:ok, %{neighbourhoods: [], remote: "skipped"}}

  @doc """
  Stores the place a search suggested (ADR-188) and returns it with its id.
  An address becomes the neighbourhood around it; the address is not kept.
  """
  def import_place(ref) when is_binary(ref) do
    with {:ok, suggestion} <- verify_ref(ref),
         {:ok, place} <- Places.import_neighbourhood(area(suggestion)) do
      {:ok, %{neighbourhood: present(place)}}
    end
  end

  def import_place(_ref), do: {:error, :invalid_place_ref}

  defp remote_suggestions(query, local) do
    query = String.trim(query)

    # A number in the query reads as an address: only the geocoder has those.
    address? = String.match?(query, ~r/\d/)

    if String.length(query) < @remote_min_chars or
         (length(local) >= @remote_below and not address?) do
      {[], "skipped"}
    else
      opts = [layers: Places.geocoder_layers(), limit: @remote_limit]

      case geocode_both(fn language -> geocoder().search(query, [language: language] ++ opts) end) do
        {:ok, own, english} ->
          suggestions =
            own |> Places.world_suggestions(english) |> Places.without_known_places(local)

          {suggestions, "ok"}

        :error ->
          {[], "unavailable"}
      end
    end
  end

  # Local names and English names of the same results; English is optional.
  defp geocode_both(lookup) do
    [own, english] =
      ["default", "en"]
      |> Task.async_stream(lookup, timeout: @remote_timeout_ms, on_timeout: :kill_task)
      |> Enum.map(fn
        {:ok, {:ok, results}} -> results
        _failed -> nil
      end)

    if own, do: {:ok, own, english || []}, else: :error
  end

  defp area(suggestion) do
    if Places.address_place?(suggestion) do
      opts = [layers: Places.geocoder_area_layers(), limit: 1]

      reverse = fn language ->
        geocoder().reverse(
          suggestion.latitude,
          suggestion.longitude,
          [language: language] ++ opts
        )
      end

      case geocode_both(reverse) do
        {:ok, own, english} -> Places.area_for_address(suggestion, own, english)
        :error -> Places.area_for_address(suggestion, nil, nil)
      end
    else
      suggestion
    end
  end

  defp present_suggestion(suggestion) do
    suggestion
    |> Map.take([
      :id,
      :slug,
      :kind,
      :name,
      :name_en,
      :context,
      :context_en,
      :latitude,
      :longitude
    ])
    |> Map.merge(%{city_slug: nil, ref: SignedToken.sign(@ref_salt, Map.delete(suggestion, :id))})
  end

  defp verify_ref(ref) do
    case SignedToken.verify(@ref_salt, ref, max_age: @ref_max_age_s) do
      {:ok, %{slug: slug} = suggestion} ->
        {:ok, Map.put(suggestion, :id, Places.world_place_id(slug))}

      _invalid ->
        {:error, :invalid_place_ref}
    end
  end

  defp geocoder, do: Application.fetch_env!(:palee, :geocoder)

  def get(context) do
    {:ok, %{neighbourhoods: context |> Places.home_area() |> Enum.map(&present/1)}}
  end

  def put(context, ids, now \\ DateTime.utc_now())

  def put(context, ids, now) when is_list(ids) do
    ids = ids |> Enum.map(&normalize_id/1) |> Enum.uniq()

    cond do
      Enum.any?(ids, &is_nil/1) ->
        {:error, [neighbourhood_ids: "must be ids"]}

      length(ids) > Places.max_neighbourhoods() ->
        {:error, [neighbourhood_ids: "at most #{Places.max_neighbourhoods()}"]}

      length(Places.neighbourhoods(ids)) != length(ids) ->
        {:error, [neighbourhood_ids: "has an unknown place"]}

      true ->
        with :ok <- Places.replace_home_area(context, ids, now), do: get(context)
    end
  end

  def put(_context, _ids, _now), do: {:error, [neighbourhood_ids: "must be a list"]}

  @doc "A gazetteer place as the API shows it (centroids are public reference data)."
  def present(place) do
    place
    |> Map.take([:id, :slug, :kind, :name, :name_en, :city_slug, :latitude, :longitude])
    |> Map.merge(%{context: place[:context], context_en: place[:context_en]})
  end

  defp normalize_id(id) when is_binary(id) do
    case Ecto.UUID.cast(id) do
      {:ok, id} -> id
      :error -> nil
    end
  end

  defp normalize_id(_id), do: nil
end
