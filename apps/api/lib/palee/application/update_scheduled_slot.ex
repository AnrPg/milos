defmodule Palee.Application.UpdateScheduledSlot do
  @moduledoc """
  Edits a class. A class of a series can take the edit alone, or pass it on
  to every upcoming class of its series or to those in a date range
  (ADR-200, `Palee.Scheduling.Domain.SeriesEdit`): all of them or none.
  """

  alias Palee.Application.{
    ClassLocation,
    ClassWorkoutFiling,
    PromoteClassWaitlist,
    ScheduleRealtime,
    SeriesScope
  }

  alias Palee.Scheduling
  alias Palee.Scheduling.Domain.SeriesEdit
  alias Palee.Workouts

  @doc "Edits only this class; see `update_in_scope/3` for a series."
  def call(context, id, params) do
    with {:ok, %{slot: slot}} <-
           update_in_scope(context, id, Map.drop(params, SeriesScope.keys())),
         do: {:ok, slot}
  end

  def call(_id, _params), do: {:error, :organization_context_required}

  @doc """
  Edits the class and, by `series_scope` and `every`, the other classes of
  its series. Returns the edited class and how many classes changed in all.
  """
  def update_in_scope(%{organization_id: _} = context, id, params) do
    master_workout_id = params[:master_workout_id] || params["master_workout_id"]
    class_type_id = params[:class_type_id] || params["class_type_id"]

    with {:ok, scope} <- SeriesScope.read(params),
         params = Map.drop(params, SeriesScope.keys()),
         {:ok, _workout} <- fetch_workout(context, master_workout_id),
         {:ok, _class_type} <- fetch_class_type(context, class_type_id),
         :ok <-
           ClassLocation.check_change(context, params, ClassLocation.class_location(context, id)),
         {:ok, resolved} <- SeriesScope.resolve(context, id, scope),
         {:ok, {slot, others}} <- update(context, params, resolved) do
      Enum.each([slot | others], &after_update(context, &1))
      {:ok, %{slot: slot, updated_count: 1 + length(others)}}
    end
  end

  defp update(context, params, %{series: nil, current: current}) do
    with {:ok, slot} <- update_one(context, current.id, params), do: {:ok, {slot, []}}
  end

  defp update(context, params, %{current: current, series: series, targets: targets} = resolved) do
    timezone = series.timezone
    now = DateTime.utc_now()
    shared = SeriesEdit.shared_changes(params)
    time = SeriesEdit.new_local_time(current.scheduled_at, value(params, :scheduled_at), timezone)

    Scheduling.transaction(context, fn ->
      with {:ok, slot} <- update_one(context, current.id, params),
           {:ok, others} <- update_targets(context, targets, shared, time, timezone, now),
           :ok <- update_template(context, resolved, shared, time) do
        {:ok, {slot, others}}
      end
    end)
  end

  defp update_targets(context, targets, shared, time, timezone, now) do
    Enum.reduce_while(targets, {:ok, []}, fn target, {:ok, acc} ->
      changes = SeriesEdit.changes_for(target, shared, time, timezone, now)

      case Scheduling.update_slot(context, target.id, changes) do
        {:ok, slot} -> {:cont, {:ok, [slot | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, slots} -> {:ok, Enum.reverse(slots)}
      error -> error
    end
  end

  # Only an edit to every upcoming class becomes the series's own.
  defp update_template(context, resolved, shared, time) do
    if SeriesScope.whole_series?(resolved) do
      case Scheduling.update_class_series(
             context,
             resolved.series.id,
             SeriesEdit.template_changes(shared, time)
           ) do
        {:ok, _series} -> :ok
        error -> error
      end
    else
      :ok
    end
  end

  defp update_one(context, id, params) do
    ClassWorkoutFiling.with_filed_workout(
      context,
      params,
      &update_slot(&1, id, &2),
      current_workout_id(context, id)
    )
  end

  defp after_update(context, slot) do
    broadcast_slot_updated(slot)
    # A larger capacity may admit waitlisted members (ADR-097).
    PromoteClassWaitlist.call(context, slot.id)
  end

  defp value(map, key), do: Map.get(map, key, Map.get(map, Atom.to_string(key)))

  defp update_slot(context, id, params), do: Scheduling.update_slot(context, id, params)

  defp current_workout_id(context, id) do
    case Scheduling.get_slot(context, id) do
      %{master_workout_id: workout_id} -> workout_id
      _missing -> nil
    end
  end

  # ADR-176: a class may be saved before its WOD exists.
  defp fetch_workout(_context, nil), do: {:ok, nil}
  defp fetch_workout(_context, ""), do: {:ok, nil}

  defp fetch_workout(context, id) do
    case Workouts.get_workout(context, id) do
      nil -> {:error, :workout_not_found}
      workout -> {:ok, workout}
    end
  end

  defp fetch_class_type(context, id) do
    case Scheduling.get_class_type(context, id) do
      nil -> {:error, :class_type_not_found}
      {:error, reason} -> {:error, reason}
      class_type -> {:ok, class_type}
    end
  end

  defp broadcast_slot_updated(slot) do
    ScheduleRealtime.broadcast("slot_updated", slot)
  end
end
