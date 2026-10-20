defmodule MilosTraining.Application.AroundArea do
  @moduledoc """
  «Η περιοχή μου» (ADR-154): the neighbourhoods a member searches Γύρω μου
  from by default, private to them, picked from the gazetteer. The first
  one is the main neighbourhood: when the person opts in to «Φαίνομαι στο
  Γύρω μου», their public posts show at its centroid.
  """

  alias MilosTraining.Places

  @doc "Gazetteer places for a picker, matching `query` (cities first)."
  def neighbourhoods(query) when is_binary(query),
    do:
      {:ok, %{neighbourhoods: query |> Places.search_neighbourhoods(20) |> Enum.map(&present/1)}}

  def neighbourhoods(_query), do: {:ok, %{neighbourhoods: []}}

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
    Map.take(place, [:id, :slug, :kind, :name, :name_en, :city_slug, :latitude, :longitude])
  end

  defp normalize_id(id) when is_binary(id) do
    case Ecto.UUID.cast(id) do
      {:ok, id} -> id
      :error -> nil
    end
  end

  defp normalize_id(_id), do: nil
end
