defmodule Palee.Scheduling.Domain.SeriesEdit do
  @moduledoc """
  Which classes of a series an edit reaches, and what each one gets (ADR-200).

  Staff edit one class of a series and choose how far the edit goes:

    * `:this` - only the edited class;
    * `:all` - every upcoming class of the series, and the series itself, so
      classes created later get the edit too;
    * `{:range, from, to}` - upcoming classes whose gym-local date falls in
      `from..to` (inclusive); the series itself is unchanged.

  Classes that already started are history and are never touched. The edited
  class gets the whole edit (its date and its WOD included). The other classes
  get the shared fields and, when the start time of day changed, the new time
  on their own date: their dates and their WODs stay their own.
  """

  alias Palee.Scheduling.Domain.RecurrenceRule

  @shared ~w(name class_type_id duration_minutes capacity auto_approve booking_timeout_minutes location_id coach_user_id)

  @type scope :: :this | :all | {:range, Date.t(), Date.t()}

  @doc "Reads `series_scope` (`this`, `all`, `range` with `range_from`/`range_to`)."
  @spec scope(map()) :: {:ok, scope()} | {:error, :invalid_series_scope | :series_range_required}
  def scope(params) do
    case value(params, :series_scope) do
      nil -> {:ok, :this}
      "this" -> {:ok, :this}
      "all" -> {:ok, :all}
      "range" -> range(value(params, :range_from), value(params, :range_to))
      _other -> {:error, :invalid_series_scope}
    end
  end

  defp range(from, to) do
    with {:ok, from} <- date(from),
         {:ok, to} <- date(to),
         false <- Date.after?(from, to) do
      {:ok, {:range, from, to}}
    else
      _invalid -> {:error, :series_range_required}
    end
  end

  @max_every 52

  @doc """
  Reads `every` (ADR-200 §3): 1 reaches every class in the scope, 2 every
  other one, and so on, counted from the edited class in date order.
  """
  @spec every(map()) :: {:ok, pos_integer()} | {:error, :invalid_series_every}
  def every(params) do
    case value(params, :every) do
      nil -> {:ok, 1}
      n when is_integer(n) and n in 1..@max_every -> {:ok, n}
      n when is_binary(n) -> n |> Integer.parse() |> parsed_every()
      _other -> {:error, :invalid_series_every}
    end
  end

  defp parsed_every({n, ""}) when n in 1..@max_every, do: {:ok, n}
  defp parsed_every(_invalid), do: {:error, :invalid_series_every}

  @doc """
  Keeps every `n`th of `targets`, counting from the edited class (at
  `edited_at`) in date order, both forwards and backwards.
  """
  @spec every_nth([map()], DateTime.t(), pos_integer()) :: [map()]
  def every_nth(targets, _edited_at, 1), do: targets

  def every_nth(targets, edited_at, n) do
    ordered =
      Enum.sort_by(
        [%{id: :edited, scheduled_at: edited_at} | targets],
        & &1.scheduled_at,
        DateTime
      )

    origin = Enum.find_index(ordered, &(&1.id == :edited))

    ordered
    |> Enum.with_index()
    |> Enum.filter(fn {item, index} ->
      item.id != :edited and rem(abs(index - origin), n) == 0
    end)
    |> Enum.map(&elem(&1, 0))
  end

  @doc "The latest date a scope reaches, or nil when it reaches every class."
  def last_date({:range, _from, to}), do: to
  def last_date(_scope), do: nil

  @doc """
  The other classes the edit reaches: upcoming ones (`after` `now`) inside the
  scope, without the edited class itself.
  """
  @spec targets([map()], scope(), String.t(), Ecto.UUID.t(), DateTime.t()) :: [map()]
  def targets(_occurrences, :this, _timezone, _edited_id, _now), do: []

  def targets(occurrences, scope, timezone, edited_id, now) do
    Enum.filter(occurrences, fn occurrence ->
      occurrence.id != edited_id and DateTime.compare(occurrence.scheduled_at, now) == :gt and
        in_scope?(occurrence.scheduled_at, scope, timezone)
    end)
  end

  defp in_scope?(_scheduled_at, :all, _timezone), do: true

  defp in_scope?(scheduled_at, {:range, from, to}, timezone) do
    local = scheduled_at |> DateTime.shift_zone!(timezone) |> DateTime.to_date()
    not Date.before?(local, from) and not Date.after?(local, to)
  end

  @doc "The fields of the edit that every reached class takes (string keys)."
  @spec shared_changes(map()) :: map()
  def shared_changes(params) do
    @shared
    |> Enum.filter(&(Map.has_key?(params, &1) or Map.has_key?(params, String.to_atom(&1))))
    |> Map.new(&{&1, value(params, String.to_atom(&1))})
  end

  @doc """
  The new start time of day on the gym's clock, or nil when the edit keeps
  the edited class's time (moving only its date never moves the others).
  """
  @spec new_local_time(DateTime.t(), term(), String.t()) :: Time.t() | nil
  def new_local_time(%DateTime{} = original, edited_at, timezone) do
    with {:ok, edited} <- datetime(edited_at),
         before = local_time(original, timezone),
         after_edit = local_time(edited, timezone),
         false <- Time.compare(before, after_edit) == :eq do
      after_edit
    else
      _same -> nil
    end
  end

  @doc """
  What one reached class gets: the shared fields, and its own date at the new
  time when the time of day changed. It keeps its own time when the new one
  does not exist on its date (a spring-forward gap) or is already past.
  """
  @spec changes_for(map(), map(), Time.t() | nil, String.t(), DateTime.t()) :: map()
  def changes_for(_occurrence, shared, nil, _timezone, _now), do: shared

  def changes_for(occurrence, shared, %Time{} = time, timezone, now) do
    date = occurrence.scheduled_at |> DateTime.shift_zone!(timezone) |> DateTime.to_date()

    # A new time already past today (or missing on a DST change) keeps the
    # class's own time rather than failing the whole edit.
    with {:ok, scheduled_at} <- RecurrenceRule.at_local_time(date, time, timezone),
         :gt <- DateTime.compare(scheduled_at, now) do
      Map.put(shared, "scheduled_at", scheduled_at)
    else
      _keep -> shared
    end
  end

  @doc "What the series itself takes for `:all`: the shared fields and the new time."
  @spec template_changes(map(), Time.t() | nil) :: map()
  def template_changes(shared, time) do
    if time, do: Map.put(shared, "local_start_time", time), else: shared
  end

  defp local_time(datetime, timezone) do
    datetime |> DateTime.shift_zone!(timezone) |> DateTime.to_time() |> Time.truncate(:second)
  end

  defp datetime(%DateTime{} = datetime), do: {:ok, datetime}

  defp datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> {:ok, datetime}
      _invalid -> :error
    end
  end

  defp datetime(_value), do: :error

  defp date(%Date{} = date), do: {:ok, date}
  defp date(value) when is_binary(value), do: Date.from_iso8601(value)
  defp date(_value), do: :error

  defp value(map, key), do: Map.get(map, key, Map.get(map, Atom.to_string(key)))
end
