defmodule Palee.Application.CleaningLog do
  @moduledoc """
  The cleaning log (ADR-102) on top of the gym's spaces (ADR-202).

  The cleaning areas became spaces: `/cleaning/areas` keeps answering with
  the spaces (and their task checklists), so the log's API is unchanged.
  A space may have a cleaning schedule (weekdays, times, comment); the
  janitor's «Σήμερα» lists what is due today, with the floor plans the
  spaces are drawn on so they can be ticked off by tapping them.

  Branch-scoped staff (ADR-186) see and clean the spaces of their branches.
  """

  alias Palee.{Housekeeping, Organizations, Spaces}
  alias Palee.Application.SpaceDirectory
  alias Palee.TimeZones.ZonedTime

  @doc "The spaces as cleaning areas, with when each was last cleaned."
  def areas(context, filters \\ %{}) do
    spaces = scoped_spaces(context, filters)
    last = Housekeeping.last_cleaned(context, Enum.map(spaces, & &1.id))

    Enum.map(spaces, &area(&1, Map.get(last, &1.id)))
  end

  @doc "Adds a cleaning area: a space with tasks (ADR-102's API)."
  def create_area(context, params) do
    with :ok <- Organizations.authorize_location(context, Map.get(params, :location_id)),
         {:ok, space} <-
           Spaces.create_space(context, Map.take(params, [:name, :location_id, :tasks])) do
      {:ok, area(space, nil)}
    end
  end

  def update_area(context, id, params) do
    with {:ok, space} <- SpaceDirectory.fetch(context, id),
         :ok <- moved_in_scope(context, params),
         {:ok, space} <-
           Spaces.update_space(context, space.id, Map.take(params, [:name, :location_id, :tasks])) do
      {:ok, area(space, last_cleaned(context, space.id))}
    end
  end

  def archive_area(context, id) do
    with {:ok, space} <- SpaceDirectory.fetch(context, id),
         {:ok, space} <- Spaces.archive_space(context, space.id) do
      {:ok, area(space, last_cleaned(context, space.id))}
    end
  end

  @doc "Starts cleaning a space."
  def start(context, area_id, now \\ DateTime.utc_now()) do
    with {:ok, space} <- in_scope(context, area_id),
         do: Housekeeping.start(context, context.user_id, space, now)
  end

  @doc "Finishes the caller's cleaning with the tasks done and an optional note."
  def finish(context, entry_id, params, now \\ DateTime.utc_now()) do
    with %{} = entry <- Housekeeping.get_entry(context, entry_id) || {:error, :not_found},
         %{} = space <- Spaces.get_space(context, entry.area_id) || {:error, :not_found} do
      Housekeeping.finish(context, context.user_id, entry, space, params, now)
    end
  end

  @doc "The log: everyone's for reviewers, the caller's own otherwise."
  def entries(context, params) do
    filters =
      %{area_id: Map.get(params, :area_id)}
      |> then(fn filters ->
        if Organizations.can?(context, :review_cleaning),
          do: filters,
          else: Map.put(filters, :user_id, context.user_id)
      end)

    case Organizations.location_scope(context) do
      :all ->
        Housekeeping.list_entries(context, filters)

      _scoped ->
        ids = context |> scoped_spaces(%{include_archived: true}) |> MapSet.new(& &1.id)
        context |> Housekeeping.list_entries(filters) |> Enum.filter(&(&1.area_id in ids))
    end
  end

  # ── Schedule (ADR-202) ──────────────────────────────────────────────────

  @doc "The cleaning schedules of the spaces the caller sees."
  def schedules(context) do
    ids = context |> scoped_spaces(%{}) |> MapSet.new(& &1.id)
    context |> Housekeeping.list_schedules() |> Enum.filter(&(&1.space_id in ids))
  end

  def put_schedule(context, space_id, params) do
    with {:ok, space} <- in_scope(context, space_id),
         do: Housekeeping.put_schedule(context, space.id, params)
  end

  def delete_schedule(context, space_id) do
    with {:ok, space} <- in_scope(context, space_id),
         do: Housekeeping.delete_schedule(context, space.id)
  end

  @doc """
  «Σήμερα»: the spaces due today on the gym's clock, how many cleanings each
  still needs, the caller's open cleanings, and the floor plans of the
  branches involved, with every scheduled space drawn on them.
  """
  def today(context, now \\ DateTime.utc_now()) do
    zone = Organizations.organization_timezone(context.organization_id)
    date = ZonedTime.local_date(now, zone)
    day_start = ZonedTime.start_of_day(date, zone)
    day_end = ZonedTime.start_of_day(Date.add(date, 1), zone)

    spaces = scoped_spaces(context, %{})
    schedules = Housekeeping.list_schedules(context)

    entries =
      Housekeeping.list_entries(context, %{from: day_start, to: day_end, limit: 1_000})

    finished =
      entries
      |> Enum.filter(& &1.finished_at)
      |> Enum.frequencies_by(& &1.area_id)

    due = Housekeeping.due(spaces, schedules, finished, date)
    spaces_by_id = Map.new(spaces, &{&1.id, &1})

    floor_plan_ids =
      due
      |> Enum.map(&spaces_by_id[&1.space_id].floor_plan_id)
      |> Enum.reject(&is_nil/1)
      |> MapSet.new()

    %{
      date: date,
      due:
        Enum.map(due, fn row ->
          space = spaces_by_id[row.space_id]
          Map.merge(row, Map.take(space, [:name, :location_id, :tasks, :floor_plan_id, :area]))
        end),
      open_entries:
        Enum.filter(entries, &(is_nil(&1.finished_at) and &1.user_id == context.user_id)),
      floor_plans:
        context
        |> SpaceDirectory.list()
        |> Map.fetch!(:floor_plans)
        |> Enum.filter(&MapSet.member?(floor_plan_ids, &1.id))
    }
  end

  # ── Helpers ─────────────────────────────────────────────────────────────

  defp scoped_spaces(context, filters) do
    context
    |> Spaces.list_spaces(filters)
    |> then(&Organizations.filter_by_location_scope(context, &1))
  end

  defp in_scope(context, id) do
    case SpaceDirectory.fetch(context, id) do
      {:error, :space_not_found} -> {:error, :not_found}
      other -> other
    end
  end

  defp moved_in_scope(context, params) do
    if Map.has_key?(params, :location_id),
      do: Organizations.authorize_location(context, params.location_id),
      else: :ok
  end

  defp last_cleaned(context, id), do: context |> Housekeeping.last_cleaned([id]) |> Map.get(id)

  defp area(space, last_cleaned_at) do
    space
    |> Map.take([:id, :name, :location_id, :tasks, :archived_at, :floor_plan_id, :area])
    |> Map.put(:last_cleaned_at, last_cleaned_at)
  end
end
