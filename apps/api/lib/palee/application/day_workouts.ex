defmodule Palee.Application.DayWorkouts do
  @moduledoc """
  A WOD for a whole gym day (ADR-230).

  Staff set a WOD on a date, for every class or for chosen class types (and,
  in a gym with branches, for one branch). The day's classes inherit it:
  the WOD is written onto each class (`master_workout_id`) together with the
  rule it came from (`day_workout_id`), so everything that reads a class's
  WOD (members, bookings, drafts, the missing-WOD alerts, results) needs no
  second lookup. A class's own WOD beats the day's (an override) until staff
  reset it to the day's WOD.

  Inheritance is re-applied, for the dates concerned, whenever a rule is set
  or removed and whenever classes are created or moved
  (`reconcile_classes/2`), so classes created after the day WOD inherit it
  too. Rules for one date are applied in one transaction.

  Days are gym days (ADR-176); the WOD is the copy filed in that day's
  Classes folder, which every class of the day shares.
  """

  alias Palee.Application.{ClassWorkoutFiling, ScheduleRealtime}
  alias Palee.{Organizations, Scheduling, Workouts}
  alias Palee.Scheduling.DayWorkoutStore
  alias Palee.Scheduling.Domain.DayWorkoutInheritance
  alias Palee.TimeZones.ZonedTime

  @max_class_types 50

  @doc "The day WODs of the dates in [from, to], with their WOD's title and type."
  def list(%{organization_id: _} = context, %Date{} = from, %Date{} = to) do
    context
    |> DayWorkoutStore.list_rules(from, to)
    |> Enum.filter(&visible?(context, &1))
    |> with_workouts(context)
  end

  @doc """
  What setting a day WOD would do, before it is saved: the classes that
  would take it, those keeping their own WOD, and those already started.
  """
  def preview(%{organization_id: _} = context, params) do
    with {:ok, request} <- read_request(context, params) do
      candidate_rules =
        Enum.map(request.class_type_ids, fn type_id ->
          %{
            id: :candidate,
            class_type_id: type_id,
            location_id: request.location_id,
            master_workout_id: request.master_workout_id
          }
        end)

      rules =
        context
        |> DayWorkoutStore.list_rules(request.date, request.date)
        |> DayWorkoutInheritance.with_candidates(candidate_rules)

      {:ok,
       context
       |> day_classes(request.date)
       |> scoped_classes(context)
       |> DayWorkoutInheritance.preview(rules, DateTime.utc_now(), [:candidate])
       |> Map.new(fn {bucket, list} -> {bucket, Enum.map(list, &class_summary/1)} end)}
    end
  end

  @doc """
  Sets the WOD of a day for each of `class_type_ids` (none = every class)
  and `location_id` (nil = every branch), replacing the WOD of a scope that
  already had one. `replace_own: true` also replaces the WODs set on single
  classes in that scope.
  """
  def set(%{organization_id: _} = context, params) do
    with {:ok, request} <- read_request(context, params),
         {:ok, %{rules: rules, changed_ids: changed_ids}} <- file_and_save(context, request) do
      after_change(context, changed_ids)

      {:ok,
       %{
         day_workouts: with_workouts(rules, context),
         changed_count: length(changed_ids)
       }}
    end
  end

  def set(_context, _params), do: {:error, :organization_context_required}

  @doc """
  Removes a day WOD. Its classes fall back to a broader day WOD, or to none;
  a standalone class people booked keeps the WOD as its own (ADR-176).
  """
  def clear(%{organization_id: _} = context, rule_id) do
    with %{} = rule <- DayWorkoutStore.get_rule(context, rule_id) || {:error, :not_found},
         :ok <- Organizations.authorize_location(context, rule.location_id),
         {:ok, changed_ids} <-
           DayWorkoutStore.transaction(context, fn ->
             # Classes are re-pointed first: deleting the rule would blank
             # their link and make inherited WODs look like their own.
             with {:ok, changed_ids} <-
                    reconcile_date(context, rule.local_date, without_rule_id: rule.id),
                  {:ok, _deleted} <- DayWorkoutStore.delete_rule(context, rule.id),
                  do: {:ok, changed_ids}
           end) do
      after_change(context, changed_ids)
      {:ok, %{day_workout: rule, changed_count: length(changed_ids)}}
    end
  end

  def clear(_context, _rule_id), do: {:error, :organization_context_required}

  @doc """
  Gives a class back the day's WOD in place of its own
  («Επαναφορά στο WOD ημέρας»). `{:error, :no_day_workout}` when no day WOD
  covers it.
  """
  def reset_class(%{organization_id: _} = context, slot_id) do
    with %{} = slot <- Scheduling.get_slot(context, slot_id) || {:error, :not_found},
         :ok <- Organizations.authorize_location(context, Map.get(slot, :location_id)),
         :ok <- ensure_not_started(slot),
         date = local_date(context, slot.scheduled_at),
         class = Enum.find(day_classes(context, date), &(&1.id == slot.id)),
         rules = DayWorkoutStore.list_rules(context, date, date),
         %{} = rule <- DayWorkoutInheritance.winner(rules, class) || {:error, :no_day_workout},
         {:ok, changed_ids} <-
           DayWorkoutStore.apply_changes(context, [{slot.id, {:inherit, rule}}]) do
      after_change(context, changed_ids)
      {:ok, Scheduling.get_slot(context, slot.id)}
    end
  end

  def reset_class(_context, _slot_id), do: {:error, :organization_context_required}

  @doc """
  Re-applies the day WODs to the days of `slots` (just created or moved),
  so they inherit like the classes that were there first. Returns the ids
  of the classes that changed; no-op for days without a day WOD.
  """
  def reconcile_classes(%{organization_id: _} = context, slots) when is_list(slots) do
    dates =
      slots
      |> Enum.map(&Map.get(&1, :scheduled_at))
      |> Enum.filter(&match?(%DateTime{}, &1))
      |> Enum.map(&local_date(context, &1))
      |> Enum.uniq()

    reconcile_dates(context, dates)
  end

  def reconcile_classes(_context, _slots), do: {:ok, []}

  @doc """
  Re-applies the day WODs of the gym dates in [from, to] that have one: for
  classes created in bulk (a new series, a series extended a year ahead).
  """
  def reconcile_range(%{organization_id: _} = context, %Date{} = from, %Date{} = to) do
    dates =
      context
      |> DayWorkoutStore.list_rules(from, to)
      |> Enum.map(& &1.local_date)
      |> Enum.uniq()

    reconcile_dates(context, dates)
  end

  def reconcile_range(_context, _from, _to), do: {:ok, []}

  @doc "Re-applies the day WODs of `dates` (gym dates); see `reconcile_classes/2`."
  def reconcile_dates(_context, []), do: {:ok, []}

  def reconcile_dates(%{organization_id: _} = context, dates) do
    {from, to} = Enum.min_max_by(dates, & &1, Date)

    dated =
      context
      |> DayWorkoutStore.list_rules(from, to)
      |> MapSet.new(& &1.local_date)

    # Dates without a rule can still hold classes that inherited elsewhere
    # (a class moved away from its day WOD), so they are checked too.
    dates
    |> Enum.reduce_while({:ok, []}, fn date, {:ok, acc} ->
      opts = if MapSet.member?(dated, date), do: [], else: [only_inherited: true]

      case reconcile_date(context, date, opts) do
        {:ok, ids} -> {:cont, {:ok, acc ++ ids}}
        error -> {:halt, error}
      end
    end)
    |> tap(fn
      {:ok, ids} -> after_change(context, ids)
      _error -> :ok
    end)
  end

  # Writes the rules of the request and applies the day's inheritance, all
  # in one transaction; the WOD is filed in the day's Classes folder first.
  defp file_and_save(context, request) do
    ClassWorkoutFiling.with_filed_workout(
      context,
      %{
        master_workout_id: request.master_workout_id,
        scheduled_at: midday(context, request.date)
      },
      fn context, %{master_workout_id: filed_id} ->
        DayWorkoutStore.transaction(context, fn ->
          with {:ok, rules} <- put_rules(context, request, filed_id),
               {:ok, changed_ids} <-
                 reconcile_date(context, request.date,
                   replace_own: request.replace_own,
                   only_rule_ids: Enum.map(rules, & &1.id)
                 ) do
            {:ok, %{rules: rules, changed_ids: changed_ids}}
          end
        end)
      end
    )
  end

  defp put_rules(context, request, workout_id) do
    request.class_type_ids
    |> Enum.reduce_while({:ok, []}, fn type_id, {:ok, acc} ->
      context
      |> DayWorkoutStore.put_rule(%{
        local_date: request.date,
        class_type_id: type_id,
        location_id: request.location_id,
        master_workout_id: workout_id,
        set_by_id: Map.get(context, :user_id)
      })
      |> case do
        {:ok, rule} -> {:cont, {:ok, [rule | acc]}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, rules} -> {:ok, Enum.reverse(rules)}
      error -> error
    end
  end

  defp reconcile_date(context, date, opts) do
    without = Keyword.get(opts, :without_rule_id)

    rules =
      context
      |> DayWorkoutStore.list_rules(date, date)
      |> Enum.reject(&(&1.id == without))

    classes = day_classes(context, date)
    now = DateTime.utc_now()

    classes =
      if Keyword.get(opts, :only_inherited, false),
        do: Enum.filter(classes, &DayWorkoutInheritance.inherited?/1),
        else: classes

    changes =
      for class <- classes,
          change = DayWorkoutInheritance.change(class, rules, now, opts),
          change != :keep,
          do: {class.id, change}

    DayWorkoutStore.apply_changes(context, changes)
  end

  defp day_classes(context, date) do
    zone = zone(context)

    DayWorkoutStore.list_classes(
      context,
      ZonedTime.start_of_day(date, zone),
      ZonedTime.start_of_day(Date.add(date, 1), zone)
    )
  end

  # ADR-186: an all-branches day WOD reaches every branch, so everyone sees it.
  defp visible?(context, rule),
    do: is_nil(rule.location_id) or Organizations.location_in_scope?(context, rule.location_id)

  # ADR-186: branch-scoped staff only see and change their branches' classes.
  defp scoped_classes(classes, context),
    do: Organizations.filter_by_location_scope(context, classes)

  defp after_change(_context, []), do: :ok

  defp after_change(context, changed_ids) do
    context
    |> Scheduling.list_slots_by_ids(changed_ids)
    |> Enum.each(&ScheduleRealtime.broadcast("slot_updated", &1))
  end

  # -- request ---------------------------------------------------------------

  defp read_request(context, params) do
    with {:ok, date} <- read_date(context, value(params, :date)),
         {:ok, type_ids} <- read_class_types(context, value(params, :class_type_ids)),
         location_id = blank_to_nil(value(params, :location_id)),
         :ok <- Organizations.authorize_location(context, location_id),
         {:ok, workout_id} <- read_workout(context, value(params, :master_workout_id)) do
      {:ok,
       %{
         date: date,
         class_type_ids: type_ids,
         location_id: location_id,
         master_workout_id: workout_id,
         replace_own: value(params, :replace_own) in [true, "true"]
       }}
    end
  end

  defp read_date(context, value) do
    with {:ok, date} <- parse_date(value) do
      if Date.before?(date, Organizations.local_today(context.organization_id)),
        do: {:error, :day_in_the_past},
        else: {:ok, date}
    end
  end

  defp parse_date(%Date{} = date), do: {:ok, date}

  defp parse_date(value) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> {:ok, date}
      _invalid -> {:error, :invalid_date}
    end
  end

  defp parse_date(_value), do: {:error, :invalid_date}

  # No types (or an empty list) = every class: one rule without a type.
  defp read_class_types(_context, value) when value in [nil, []], do: {:ok, [nil]}

  defp read_class_types(context, ids) when is_list(ids) and length(ids) <= @max_class_types do
    ids = Enum.uniq(ids)

    if Enum.all?(ids, &active_class_type?(context, &1)),
      do: {:ok, ids},
      else: {:error, :class_type_not_found}
  end

  defp read_class_types(_context, _value), do: {:error, :class_type_not_found}

  defp active_class_type?(context, id) when is_binary(id) do
    case Scheduling.get_class_type(context, id) do
      %{archived_at: nil} -> true
      _missing_or_archived -> false
    end
  end

  defp active_class_type?(_context, _id), do: false

  defp read_workout(context, id) when is_binary(id) and id != "" do
    case Workouts.get_workout(context, id) do
      nil -> {:error, :workout_not_found}
      _workout -> {:ok, id}
    end
  end

  defp read_workout(_context, _id), do: {:error, :workout_not_found}

  defp ensure_not_started(slot) do
    if DayWorkoutInheritance.started?(slot, DateTime.utc_now()),
      do: {:error, :day_class_started},
      else: :ok
  end

  # -- presentation ------------------------------------------------------------

  defp with_workouts(rules, context) do
    titles =
      rules
      |> Enum.map(& &1.master_workout_id)
      |> Enum.uniq()
      |> Map.new(fn id -> {id, Workouts.get_workout(context, id)} end)

    Enum.map(rules, fn rule ->
      workout = Map.get(titles, rule.master_workout_id)

      Map.put(
        rule,
        :workout,
        workout && %{id: workout.id, title: workout.title, type: Map.get(workout, :type)}
      )
    end)
  end

  defp class_summary(class) do
    Map.take(class, [:id, :name, :scheduled_at, :class_type_id, :class_type_name, :location_id])
  end

  # -- clock -------------------------------------------------------------------

  defp zone(context), do: Organizations.organization_timezone(context.organization_id)

  defp local_date(context, %DateTime{} = at), do: ZonedTime.local_date(at, zone(context))

  # Any moment of the day files the WOD in that day's folder; midday is
  # safely inside it whatever the zone's DST changes.
  defp midday(context, date), do: ZonedTime.to_utc(date, ~T[12:00:00], zone(context))

  defp value(params, key), do: Map.get(params, key, Map.get(params, Atom.to_string(key)))

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value
end
