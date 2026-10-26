defmodule Palee.Scheduling.Domain.ClassState do
  @moduledoc """
  Pause, resume, cancel, restore and delete a class (ADR-200 §2).

    * `:pause` - nobody can book it; existing bookings stay. `:resume` undoes it.
    * `:cancel` - it stays on the schedule as cancelled, with an optional
      reason; every booking and waitlist place is released without a late
      penalty. `:restore` reopens it while it is upcoming (the released
      bookings do not come back).
    * `:delete` - only a class nobody ever booked; one with bookings is left
      alone (cancel it instead).

  Classes that already started are history and never change. Each class gets
  a plan: `{:change, fields}`, `:delete`, or `{:skip, reason}`.
  """

  @actions %{
    "pause" => :pause,
    "resume" => :resume,
    "cancel" => :cancel,
    "restore" => :restore,
    "delete" => :delete
  }

  @type action :: :pause | :resume | :cancel | :restore | :delete
  @type skip_reason ::
          :unchanged | :slot_in_past | :class_cancelled | :class_has_bookings
  @type plan :: {:change, map()} | :delete | {:skip, skip_reason()}

  @doc "Reads the action name."
  @spec action(term()) :: {:ok, action()} | {:error, :invalid_class_action}
  def action(name) when is_atom(name) and not is_nil(name),
    do: action(Atom.to_string(name))

  def action(name) do
    case Map.fetch(@actions, name) do
      {:ok, action} -> {:ok, action}
      :error -> {:error, :invalid_class_action}
    end
  end

  @doc "What `action` does to one class at `now`."
  @spec plan(map(), action(), DateTime.t(), String.t() | nil) :: plan()
  def plan(slot, action, now, reason \\ nil) do
    if DateTime.compare(slot.scheduled_at, now) == :gt,
      do: upcoming_plan(slot, action, now, reason),
      else: {:skip, :slot_in_past}
  end

  defp upcoming_plan(slot, :pause, now, _reason) do
    cond do
      cancelled?(slot) -> {:skip, :class_cancelled}
      paused?(slot) -> {:skip, :unchanged}
      true -> {:change, %{paused_at: now}}
    end
  end

  defp upcoming_plan(slot, :resume, _now, _reason) do
    if paused?(slot), do: {:change, %{paused_at: nil}}, else: {:skip, :unchanged}
  end

  defp upcoming_plan(slot, :cancel, now, reason) do
    if cancelled?(slot),
      do: {:skip, :unchanged},
      else: {:change, %{cancelled_at: now, cancel_reason: reason, paused_at: nil}}
  end

  defp upcoming_plan(slot, :restore, _now, _reason) do
    if cancelled?(slot),
      do: {:change, %{cancelled_at: nil, cancel_reason: nil}},
      else: {:skip, :unchanged}
  end

  defp upcoming_plan(slot, :delete, _now, _reason) do
    if Map.get(slot, :bookings, []) == [], do: :delete, else: {:skip, :class_has_bookings}
  end

  @doc """
  The bookings a cancel releases: every booking and waitlist place still
  holding a place (attended and no-show bookings are history).
  """
  @spec released_bookings(map()) :: [map()]
  def released_bookings(slot) do
    Enum.filter(Map.get(slot, :bookings, []), &(&1.status in [:pending, :approved, :waitlisted]))
  end

  @doc """
  Whether a skip of the class the person acted on is an error to show
  (rather than one of several classes left alone).
  """
  @spec refusal?(skip_reason()) :: boolean()
  def refusal?(:unchanged), do: false
  def refusal?(_reason), do: true

  @doc "Whether the series stops at this point: a whole-series cancel or delete."
  @spec ends_series?(action()) :: boolean()
  def ends_series?(action), do: action in [:cancel, :delete]

  defp paused?(slot), do: not is_nil(Map.get(slot, :paused_at))
  defp cancelled?(slot), do: not is_nil(Map.get(slot, :cancelled_at))
end
