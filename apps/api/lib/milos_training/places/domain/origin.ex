defmodule MilosTraining.Places.Domain.Origin do
  @moduledoc """
  Where a Γύρω μου search starts (ADR-154), first match wins:

  1. the filter's own neighbourhoods («Πού»): their centroids;
  2. what the request names: the saved area (`area`), the device's position
     (`point`, rounded to 3 decimals and never stored), or a one-off place
     (`place`: a gazetteer id, or a text the geocoder resolves) that leaves
     the saved area alone;
  3. the saved area, «Η περιοχή μου»;
  4. the member's box: its home location, else its first pinned location.

  An origin is `%{type, points, label, neighbourhood_ids}`; `points` are
  `{latitude, longitude}` and a search measures from the nearest of them.
  """

  alias MilosTraining.Places.Domain.SearchArea

  @types ~w(neighbourhoods area point place box)
  @uuid ~r/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/

  def types, do: @types

  @doc """
  The request's `origin` object: `nil`, `:area`, `{:point, lat, lng}` (already
  rounded), `{:neighbourhood, id}` or `{:query, text}`.
  """
  def parse_request(nil), do: {:ok, nil}

  def parse_request(%{} = spec) do
    spec = Map.new(spec, fn {key, value} -> {to_string(key), value} end)

    case spec do
      %{"type" => "area"} ->
        {:ok, :area}

      %{"type" => "point", "latitude" => latitude, "longitude" => longitude} ->
        case SearchArea.round_point(latitude, longitude) do
          {:ok, {latitude, longitude}} -> {:ok, {:point, latitude, longitude}}
          {:error, _reason} -> {:error, [origin: "has an invalid position"]}
        end

      %{"type" => "place", "neighbourhood_id" => id} when is_binary(id) ->
        if String.downcase(id) =~ @uuid,
          do: {:ok, {:neighbourhood, String.downcase(id)}},
          else: {:error, [origin: "has an invalid place id"]}

      %{"type" => "place", "query" => query} when is_binary(query) ->
        case query |> String.split() |> Enum.join(" ") do
          query when byte_size(query) >= 2 and byte_size(query) <= 200 -> {:ok, {:query, query}}
          _invalid -> {:error, [origin: "needs a place name of 2 to 200 characters"]}
        end

      _other ->
        {:error, [origin: "must be area, point or place"]}
    end
  end

  def parse_request(_spec), do: {:error, [origin: "must be an object"]}

  @doc """
  Picks the origin. `requested` is `nil`, `:area` or an origin; `home` is an
  origin, `nil`, or a zero-arity function returning one (so the box is only
  looked up when nothing else applies).
  """
  def resolve(%{neighbourhoods: neighbourhoods, requested: requested, area: area, home: home}) do
    cond do
      neighbourhoods != [] -> {:ok, from_places("neighbourhoods", neighbourhoods)}
      is_map(requested) -> {:ok, requested}
      area != [] -> {:ok, from_places("area", area)}
      true -> home_origin(home)
    end
  end

  @doc "An origin at the centroids of gazetteer places."
  def from_places(type, places) when type in @types and places != [] do
    %{
      type: type,
      points: Enum.map(places, &{&1.latitude, &1.longitude}),
      label: Enum.map_join(places, ", ", & &1.name),
      neighbourhood_ids: Enum.map(places, & &1.id)
    }
  end

  @doc "An origin at one point."
  def from_point(type, {latitude, longitude}, label) when type in @types do
    %{type: type, points: [{latitude, longitude}], label: label, neighbourhood_ids: []}
  end

  @doc "What the API shows of an origin: its type, label and first point."
  def present(%{points: [{latitude, longitude} | _rest]} = origin) do
    %{
      type: origin.type,
      label: origin.label,
      latitude: latitude,
      longitude: longitude,
      neighbourhood_ids: origin.neighbourhood_ids
    }
  end

  defp home_origin(home) when is_function(home, 0), do: home_origin(home.())
  defp home_origin(%{points: [_ | _]} = origin), do: {:ok, origin}
  defp home_origin(_none), do: {:error, :origin_required}
end
