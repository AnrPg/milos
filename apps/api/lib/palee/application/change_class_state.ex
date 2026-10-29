defmodule Palee.Application.ChangeClassState do
  @moduledoc """
  Pause, resume, cancel, restore or delete a class and, by `series_scope` and
  `every`, the other classes of its series (ADR-200 §2). The rules for each
  class are `Palee.Scheduling.Domain.ClassState`; which classes are reached is
  `Palee.Application.SeriesScope`, the same as for an edit.

  Every class changes in one transaction: all of them or none. A class the
  action can't take (started, already cancelled, booked for a delete) is
  left alone and counted; when it was the only class reached, the action is
  refused with the reason. A cancel releases every booking and waitlist place
  of the class without a late penalty and tells the members. A cancel or
  delete of every upcoming class ends the series, so it creates no more.
  """

  alias Palee.Application.{
    ClassLocation,
    PromoteClassWaitlist,
    ScheduleRealtime,
    SeriesScope,
    TrackAnalyticsEvent,
    WithdrawBooking
  }

  alias Palee.{Notifications, Scheduling}
  alias Palee.Scheduling.Domain.ClassState

  @release_reason "Class cancelled"

  def call(%{organization_id: _} = context, id, params) do
    with {:ok, action} <- ClassState.action(value(params, :action)),
         {:ok, scope} <- SeriesScope.read(params),
         :ok <- ClassLocation.authorize_class(context, id),
         {:ok, resolved} <- SeriesScope.resolve(context, id, scope),
         now = DateTime.utc_now(),
         plans = plans(context, resolved, action, now, reason(params)),
         :ok <- refusal(plans, resolved),
         {:ok, outcome} <- apply_plans(context, plans, resolved, action) do
      after_commit(context, outcome, action, now)
      {:ok, summary(outcome, plans, action)}
    end
  end

  def call(_id, _params), do: {:error, :organization_context_required}

  defp plans(context, resolved, action, now, reason) do
    reached = SeriesScope.reached(resolved)

    slots =
      Map.new(
        Scheduling.list_slots_by_ids(context, Enum.map(reached, & &1.id)),
        &{&1.id, &1}
      )

    reached
    |> Enum.map(&Map.get(slots, &1.id))
    |> Enum.reject(&is_nil/1)
    |> Enum.map(&{&1, ClassState.plan(&1, action, now, reason)})
  end

  # Acting on one class that can't take the action says why.
  defp refusal([{_slot, {:skip, reason}}], _resolved) do
    if ClassState.refusal?(reason), do: {:error, reason}, else: :ok
  end

  defp refusal(_plans, _resolved), do: :ok

  defp apply_plans(context, plans, resolved, action) do
    Scheduling.transaction(context, fn ->
      with {:ok, outcome} <- apply_each(context, plans),
           :ok <- end_series(context, resolved, action) do
        {:ok, outcome}
      end
    end)
  end

  defp apply_each(context, plans) do
    plans
    |> Enum.reduce_while({:ok, %{changed: [], deleted: [], released: []}}, fn plan, {:ok, acc} ->
      case apply_plan(context, plan) do
        {:ok, outcome} -> {:cont, {:ok, merge(acc, outcome)}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp apply_plan(_context, {_slot, {:skip, _reason}}), do: {:ok, %{}}

  defp apply_plan(context, {slot, :delete}) do
    with :ok <- Scheduling.delete_slot(context, slot.id), do: {:ok, %{deleted: [slot]}}
  end

  defp apply_plan(context, {slot, {:change, %{cancelled_at: %DateTime{}} = fields}}) do
    with {:ok, released} <- release_bookings(context, slot),
         {:ok, changed} <- Scheduling.set_slot_state(context, slot.id, fields) do
      {:ok, %{changed: [changed], released: Enum.map(released, &{&1, changed})}}
    end
  end

  defp apply_plan(context, {slot, {:change, fields}}) do
    with {:ok, changed} <- Scheduling.set_slot_state(context, slot.id, fields),
         do: {:ok, %{changed: [changed]}}
  end

  # The visit goes back with a durable job written with the withdrawal; the
  # immediate return runs after the commit.
  defp release_bookings(context, slot) do
    slot
    |> ClassState.released_bookings()
    |> Enum.reduce_while({:ok, []}, fn booking, {:ok, acc} ->
      booking = Map.put(booking, :scheduled_class_id, slot.id)

      case Scheduling.withdraw_booking(
             context,
             booking.id,
             WithdrawBooking.reconciliation(booking, false, @release_reason)
           ) do
        {:ok, _withdrawn} -> {:cont, {:ok, [booking | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp end_series(context, resolved, action) do
    if SeriesScope.whole_series?(resolved) and ClassState.ends_series?(action) do
      case Scheduling.update_class_series(context, resolved.series.id, %{"status" => "ended"}) do
        {:ok, _series} -> :ok
        error -> error
      end
    else
      :ok
    end
  end

  defp after_commit(context, outcome, action, now) do
    Enum.each(outcome.released, fn {booking, _slot} ->
      WithdrawBooking.reconcile_now(context, booking, false, @release_reason)

      Palee.DomainEvents.publish(:booking_cancelled, %{
        organization_id: context.organization_id,
        booking_id: booking.id,
        user_id: booking.user_id,
        kind: Map.get(booking, :kind) || "member",
        by: :staff,
        at: now
      })
    end)

    Enum.each(outcome.changed, fn slot ->
      if action == :cancel, do: class_gone(context, slot.id, now)
      ScheduleRealtime.broadcast("slot_updated", slot)
      # A resumed or restored class may take its waitlist again.
      if action in [:resume, :restore], do: PromoteClassWaitlist.call(context, slot.id)
    end)

    Enum.each(outcome.deleted, fn slot ->
      class_gone(context, slot.id, now)

      ScheduleRealtime.broadcast("slot_deleted", %{
        organization_id: context.organization_id,
        slot_id: slot.id
      })
    end)

    notify_members(context, outcome.released)
    track(context, outcome, action)
  end

  defp track(context, outcome, action) do
    Enum.each(outcome.changed, fn slot ->
      TrackAnalyticsEvent.call(
        "class_state_changed",
        context,
        Map.put(slot, :action, Atom.to_string(action))
      )
    end)

    Enum.each(
      outcome.deleted,
      &TrackAnalyticsEvent.call("class_slot_cancelled", context, %{id: &1.id})
    )
  end

  # Trials in the class end and their people hear it (ADR-144).
  defp class_gone(context, slot_id, now) do
    Palee.DomainEvents.publish(:class_cancelled, %{
      organization_id: context.organization_id,
      scheduled_class_id: slot_id,
      at: now
    })
  end

  # Members hear once per class; a trial's person hears through the trial.
  defp notify_members(context, released) do
    released
    |> Enum.filter(fn {booking, _slot} -> (Map.get(booking, :kind) || "member") == "member" end)
    |> Enum.uniq_by(fn {booking, slot} -> {booking.user_id, slot.id} end)
    |> Enum.each(fn {booking, slot} ->
      Notifications.process_event("class_cancelled", %{
        user_id: booking.user_id,
        organization_id: context.organization_id,
        scheduled_class_id: slot.id,
        class_name: slot.name,
        class_starts_at: slot.scheduled_at,
        cancelled_at: slot.cancelled_at,
        reason: slot.cancel_reason
      })
    end)
  end

  defp summary(outcome, plans, action) do
    skipped = for {_slot, {:skip, reason}} <- plans, reason != :unchanged, do: reason

    %{
      action: action,
      slots: outcome.changed,
      deleted_ids: Enum.map(outcome.deleted, & &1.id),
      changed_count: length(outcome.changed) + length(outcome.deleted),
      skipped_count: length(skipped),
      skipped_with_bookings: Enum.count(skipped, &(&1 == :class_has_bookings)),
      released_count: length(outcome.released)
    }
  end

  defp merge(acc, outcome),
    do: Map.merge(acc, outcome, fn _key, left, right -> left ++ right end)

  defp reason(params) do
    case value(params, :reason) do
      reason when is_binary(reason) -> reason |> String.trim() |> blank_to_nil()
      _none -> nil
    end
  end

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(reason), do: reason

  defp value(map, key), do: Map.get(map, key, Map.get(map, Atom.to_string(key)))
end
