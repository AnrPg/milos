defmodule Palee.Application.BranchReport do
  @moduledoc """
  The page branch filter of the finance, coaching and statistics pages
  (ADR-186 §7).

  A request names `location_ids`; they are narrowed to the person's branch
  scope (`Organizations.report_filter/2`). Facts with a branch are filtered
  by it; the others by the people whose home branch is in the filter
  (`Organizations.Domain.BranchAttribution`). With `:all` nothing is
  filtered and the business totals stay exactly what they were.
  """

  alias Palee.{Analytics, Facility, Finance, Organizations}
  alias Palee.Organizations.Domain.BranchAttribution

  # How far back a person's training decides their home branch.
  @home_window_days 90

  @type t :: %{
          filter: :all | [String.t()],
          user_ids: [String.t()] | nil,
          location_ids: [String.t()] | nil,
          homes: %{optional(String.t()) => String.t()} | nil,
          locations: [map()]
        }

  @doc "Resolves the filter of a report request."
  def resolve(context, params) do
    filter = Organizations.report_filter(context, Organizations.requested_location_ids(params))
    locations = visible_locations(context)

    case filter do
      :all ->
        %{filter: :all, user_ids: nil, location_ids: nil, homes: nil, locations: locations}

      ids ->
        homes = homes(context)

        %{
          filter: ids,
          user_ids: BranchAttribution.users_at(homes, ids),
          location_ids: ids,
          homes: homes,
          locations: locations
        }
    end
  end

  @doc "Params for a store read: the people and branches of the filter, when any."
  def scope_params(params, %{filter: :all}), do: params

  def scope_params(params, %{user_ids: users, location_ids: ids}),
    do: params |> Map.put("user_ids", users) |> Map.put("location_ids", ids)

  @doc """
  One row per branch shown (the filter, or every branch the person sees) when
  there are at least two, with what `metrics` computes for its people:
  `metrics.(user_ids, location_id)` returns a map merged into the row.
  """
  def splits(context, report, metrics) when is_function(metrics, 2) do
    shown = shown_locations(report)

    if length(shown) < 2 do
      []
    else
      homes = report.homes || homes(context)
      people = BranchAttribution.by_branch(homes)

      Enum.map(shown, fn location ->
        users = Map.get(people, location.id, [])

        Map.merge(
          %{location_id: location.id, name: location.name, people: length(users)},
          metrics.(users, location.id)
        )
      end)
    end
  end

  @doc "Check-ins and attended classes per branch since `since`."
  def activity_by_branch(context, since),
    do: context |> Analytics.branch_activity(since) |> BranchAttribution.activity_by_branch()

  @doc "The filter as a response field."
  def filter_payload(%{filter: :all}), do: %{all_locations: true, location_ids: []}
  def filter_payload(%{filter: ids}), do: %{all_locations: false, location_ids: ids}

  defp homes(context) do
    since = DateTime.add(DateTime.utc_now(), -@home_window_days * 86_400, :second)

    active_ids =
      context |> Facility.list_locations() |> Enum.map(& &1.id)

    activity = context |> Analytics.branch_activity(since) |> BranchAttribution.activity_counts()

    BranchAttribution.home_branches(
      activity,
      Finance.package_location_scopes(context),
      active_ids
    )
  end

  defp visible_locations(context) do
    context
    |> Facility.list_locations()
    |> then(&Organizations.filter_by_location_scope(context, &1, fn location -> location.id end))
  end

  defp shown_locations(%{filter: :all, locations: locations}), do: locations

  defp shown_locations(%{filter: ids, locations: locations}),
    do: Enum.filter(locations, &(&1.id in ids))
end
