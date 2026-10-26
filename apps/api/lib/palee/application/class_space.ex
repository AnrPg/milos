defmodule Palee.Application.ClassSpace do
  @moduledoc """
  The optional space of a class or series (ADR-202).

  * A class may only take a usable (not archived) space of its own branch
    (a space without a branch fits any class of the gym).
  * A class is refused while its space is unavailable
    (`{:space_unavailable, window}`): on create, on a series' classes, and
    when an edit moves it into such a window or into such a space.
  * Two classes in one space at overlapping times are allowed; the schedule
    flags them (`space_overlap`) so staff see it.
  """

  alias Palee.{Scheduling, Spaces}
  alias Palee.Scheduling.Domain.{RecurrenceRule, SeriesEdit}

  @default_duration 60

  @doc "`:ok` when a new class's space (if any) is usable at its time."
  def check(context, params) when is_map(params) do
    case value(params, :space_id) do
      id when id in [nil, ""] ->
        :ok

      id ->
        with {:ok, space} <- fetch_usable(context, id),
             :ok <- Spaces.same_branch(space, blank(value(params, :location_id))) do
          case datetime(value(params, :scheduled_at)) do
            {:ok, at} -> Spaces.check_available(context, space.id, at, duration(params))
            :error -> :ok
          end
        end
    end
  end

  @doc "`check/2` for each of several new classes (one per branch)."
  def check_all(context, items, check \\ &check/2) do
    Enum.reduce_while(items, :ok, fn item, :ok ->
      case check.(context, item) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  @doc "`:ok` when every upcoming class a new series creates can use its space."
  def check_series(context, params, now \\ DateTime.utc_now()) when is_map(params) do
    case value(params, :space_id) do
      id when id in [nil, ""] ->
        :ok

      id ->
        with {:ok, space} <- fetch_usable(context, id),
             :ok <- Spaces.same_branch(space, blank(value(params, :location_id))) do
          windows = Spaces.list_unavailabilities(context, [space.id], now)
          check_occurrences(windows, series_occurrences(params, now), duration(params))
        end
    end
  end

  @doc """
  `:ok` when an edit of class `id` (and, by `scope`, the other classes of its
  series) leaves every reached class in a usable space at its time.
  """
  def check_edit(context, id, params, scope, now \\ DateTime.utc_now()) do
    with %{} = current <- Scheduling.get_slot(context, id) || {:error, :not_found} do
      space_id =
        if has?(params, :space_id), do: blank(value(params, :space_id)), else: current.space_id

      location_id =
        if has?(params, :location_id),
          do: blank(value(params, :location_id)),
          else: current.location_id

      at =
        case datetime(value(params, :scheduled_at)) do
          {:ok, at} -> at
          :error -> current.scheduled_at
        end

      minutes = value(params, :duration_minutes) || current.duration_minutes || @default_duration

      if is_nil(space_id) do
        :ok
      else
        with {:ok, space} <- fetch_usable(context, space_id, current.space_id),
             :ok <- Spaces.same_branch(space, location_id) do
          windows = Spaces.list_unavailabilities(context, [space_id], now)
          starts = [at | other_starts(context, current, params, scope, now)]
          check_occurrences(windows, starts, minutes)
        end
      end
    end
  end

  # The start of each other class the edit reaches, after the edit. A scope
  # already resolved by `SeriesScope` (with `every`) names its classes.
  defp other_starts(_context, _current, _params, %{series: nil}, _now), do: []

  defp other_starts(_context, current, params, %{series: series, targets: targets}, now) do
    time =
      SeriesEdit.new_local_time(
        current.scheduled_at,
        value(params, :scheduled_at),
        series.timezone
      )

    Enum.map(targets, fn target ->
      target
      |> SeriesEdit.changes_for(%{}, time, series.timezone, now)
      |> Map.get("scheduled_at", target.scheduled_at)
    end)
  end

  defp other_starts(_context, _current, _params, :this, _now), do: []
  defp other_starts(_context, %{class_series_id: nil}, _params, _scope, _now), do: []

  defp other_starts(context, current, params, scope, now) do
    case Scheduling.get_class_series(context, current.class_series_id) do
      %{timezone: timezone} = series ->
        time =
          SeriesEdit.new_local_time(current.scheduled_at, value(params, :scheduled_at), timezone)

        context
        |> Scheduling.list_series_slots(series.id, now)
        |> SeriesEdit.targets(scope, timezone, current.id, now)
        |> Enum.map(fn target ->
          target
          |> SeriesEdit.changes_for(%{}, time, timezone, now)
          |> Map.get("scheduled_at", target.scheduled_at)
        end)

      _missing ->
        []
    end
  end

  defp check_occurrences(windows, starts, minutes) do
    Enum.reduce_while(starts, :ok, fn at, :ok ->
      case Spaces.blocking_window(windows, at, minutes) do
        nil -> {:cont, :ok}
        window -> {:halt, {:error, {:space_unavailable, Map.put(window, :class_starts_at, at)}}}
      end
    end)
  end

  defp series_occurrences(params, now) do
    with {:ok, starts_on} <- date(value(params, :starts_on)),
         {:ok, time} <- time(value(params, :local_start_time)) do
      ends_on =
        case date(value(params, :ends_on)) do
          {:ok, date} -> date
          _none -> nil
        end

      rule = %{
        starts_on: starts_on,
        ends_on: ends_on,
        weekdays: value(params, :weekdays) || [],
        excluded_dates: parse_dates(value(params, :excluded_dates) || []),
        local_start_time: time,
        timezone: value(params, :timezone) || "Etc/UTC"
      }

      case RecurrenceRule.occurrences(rule, horizon: ends_on || Date.add(starts_on, 365)) do
        {:ok, list} -> Enum.filter(list, &(DateTime.compare(&1, now) == :gt))
        _invalid -> []
      end
    else
      _invalid -> []
    end
  end

  # The space a class already has stays acceptable to keep (even archived).
  defp fetch_usable(context, id, current_id \\ nil) do
    case Spaces.get_space(context, id) do
      %{id: ^current_id} = space when not is_nil(current_id) ->
        {:ok, space}

      space ->
        with :ok <- Spaces.usable(space), do: {:ok, space}
    end
  end

  @doc """
  Puts `space` (`%{id, name}` or nil) on each class and, for staff
  (`staff?`), `space_overlap` (another class shares the space at the same
  time) and `space_unavailable` (the space is unavailable at that time).
  """
  def annotate(_context, [], _staff?), do: []

  def annotate(context, slots, staff?) do
    ids = slots |> Enum.map(&Map.get(&1, :space_id)) |> Enum.reject(&is_nil/1) |> Enum.uniq()

    if ids == [] do
      Enum.map(slots, fn slot ->
        slot |> Map.put(:space, nil) |> staff_flags(staff?, MapSet.new(), [])
      end)
    else
      spaces =
        context
        |> Spaces.list_spaces(%{ids: ids, include_archived: true})
        |> Map.new(&{&1.id, %{id: &1.id, name: &1.name}})

      {overlaps, windows} =
        if staff? do
          from = slots |> Enum.map(& &1.scheduled_at) |> Enum.min(DateTime)
          {Spaces.overlapping_ids(slots), Spaces.list_unavailabilities(context, ids, from)}
        else
          {MapSet.new(), []}
        end

      Enum.map(slots, fn slot ->
        slot
        |> Map.put(:space, Map.get(spaces, Map.get(slot, :space_id)))
        |> staff_flags(staff?, overlaps, windows)
      end)
    end
  end

  defp staff_flags(slot, false, _overlaps, _windows), do: slot

  defp staff_flags(slot, true, overlaps, windows) do
    space_windows = Enum.filter(windows, &(&1.space_id == Map.get(slot, :space_id)))

    Map.merge(slot, %{
      space_overlap: MapSet.member?(overlaps, slot.id),
      space_unavailable:
        not is_nil(Map.get(slot, :space_id)) and
          not is_nil(
            Spaces.blocking_window(space_windows, slot.scheduled_at, slot.duration_minutes || 0)
          )
    })
  end

  defp duration(params) do
    case value(params, :duration_minutes) do
      minutes when is_integer(minutes) and minutes > 0 -> minutes
      _none -> @default_duration
    end
  end

  defp has?(params, key),
    do: Map.has_key?(params, key) or Map.has_key?(params, Atom.to_string(key))

  defp value(map, key), do: Map.get(map, key, Map.get(map, Atom.to_string(key)))

  defp blank(""), do: nil
  defp blank(value), do: value

  defp datetime(%DateTime{} = at), do: {:ok, at}

  defp datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, at, _offset} -> {:ok, at}
      _invalid -> :error
    end
  end

  defp datetime(_value), do: :error

  defp date(%Date{} = date), do: {:ok, date}
  defp date(value) when is_binary(value), do: Date.from_iso8601(value)
  defp date(_value), do: :error

  defp time(%Time{} = time), do: {:ok, time}

  defp time(value) when is_binary(value) do
    padded = if String.length(value) == 5, do: value <> ":00", else: value
    Time.from_iso8601(padded)
  end

  defp time(_value), do: :error

  defp parse_dates(list) do
    Enum.flat_map(list, fn item ->
      case date(item) do
        {:ok, date} -> [date]
        _invalid -> []
      end
    end)
  end
end
