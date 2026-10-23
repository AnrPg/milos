defmodule Palee.Application.CoveringBranches do
  @moduledoc """
  «Ισχύει για» for covering items (ADR-186 §8): a package, a promotion or a
  coaching assignment is one item valid at several branches, or at all of
  them (`:all`, future branches included).

    * Staff see an item when it is valid everywhere or at one of their
      branches (`Organizations.covering_visible?/2`).
    * They create or change one only inside their branches; `:all` needs an
      all-branch scope (`Organizations.authorize_covering/2`).
    * Branch-scoped staff who name no branches get their own.
  """

  alias Palee.Organizations

  @doc "`:all` or ids, from a stored or requested value (`\"all\"`, nil, a list)."
  def target(value) when is_list(value) and value != [], do: value |> Enum.uniq() |> Enum.sort()
  def target(_all_or_missing), do: :all

  @doc "Items visible to the acting staff; `target_of` reads an item's branches."
  def visible(context, items, target_of) when is_function(target_of, 1) do
    scope = Organizations.location_scope(context)
    Enum.filter(items, &Organizations.covering_visible?(scope, target_of.(&1)))
  end

  @doc "`:ok` when the acting staff may create or change an item valid at `target`."
  def authorize(context, target), do: Organizations.authorize_covering(context, target)

  @doc """
  The branches a new item is valid at: the requested value when given
  (checked), else everywhere for all-branch staff and the person's own
  branches otherwise. `{:ok, target}` or an error.
  """
  def for_new(context, requested) do
    case {requested, Organizations.location_scope(context)} do
      {nil, :all} -> {:ok, :all}
      {nil, scope} -> {:ok, scope}
      {value, _scope} -> with :ok <- authorize(context, target(value)), do: {:ok, target(value)}
    end
  end

  @doc "The stored shape of a target: `\"all\"` or the ids."
  def stored(:all), do: "all"
  def stored(ids) when is_list(ids), do: ids

  @doc """
  The branches a request asks for with `all_locations` / `location_ids`
  (atom or string keys): `"all"`, the ids, or nil when it names none.
  """
  def requested(params) when is_map(params) do
    all? = Map.get(params, :all_locations, Map.get(params, "all_locations"))
    ids = Map.get(params, :location_ids, Map.get(params, "location_ids"))

    cond do
      all? in [true, "true"] -> "all"
      is_list(ids) and ids != [] -> ids
      true -> nil
    end
  end

  @doc "The branches of a stored row with `all_locations` and `location_ids`."
  def of_row(%{location_scope: %{all_locations: true}}), do: :all
  def of_row(%{location_scope: %{location_ids: ids}}), do: target(ids)
  def of_row(%{all_locations: false, location_ids: ids}), do: target(ids)
  def of_row(_row), do: :all

  @doc "Params with a resolved target written as `all_locations` / `location_ids`."
  def put_columns(params, target) do
    {all?, ids} = if target == :all, do: {true, []}, else: {false, target}
    atom? = Enum.any?(Map.keys(params), &is_atom/1)

    params
    |> Map.drop([:all_locations, :location_ids, "all_locations", "location_ids"])
    |> Map.merge(
      if atom?,
        do: %{all_locations: all?, location_ids: ids},
        else: %{"all_locations" => all?, "location_ids" => ids}
    )
  end
end
