defmodule MilosTraining.Scheduling.Domain.AttendancePolicy do
  @moduledoc """
  Who may record class attendance, and when. Staff record it for approved
  bookings; a member checks themselves in to their own approved booking from
  #{30} minutes before the class until it ends (ADR-137 Box card, TD-105).
  """

  @opens_before_minutes 30

  def can_record_admin_attendance?(%{status: :approved}), do: :ok
  def can_record_admin_attendance?(%{status: "approved"}), do: :ok
  def can_record_admin_attendance?(_booking), do: {:error, :attendance_requires_approved_booking}

  @doc "When self check-in opens and closes for a class: `{opens_at, closes_at}`."
  def self_check_in_window(%{scheduled_at: %DateTime{} = starts_at} = slot) do
    duration = Map.get(slot, :duration_minutes) || 60

    {DateTime.add(starts_at, -@opens_before_minutes * 60, :second),
     DateTime.add(starts_at, duration * 60, :second)}
  end

  @doc """
  Whether a member may check in now. `existing` is their attendance record
  for the class, if any: an earlier check-in is returned as `:already`, a
  status staff recorded is never overwritten.
  """
  def self_check_in(booking, slot, existing, now) do
    {opens_at, closes_at} = self_check_in_window(slot)

    cond do
      can_record_admin_attendance?(booking) != :ok ->
        {:error, :attendance_requires_approved_booking}

      match?(%{status: "attended"}, existing) ->
        :already

      existing != nil ->
        {:error, :attendance_already_recorded}

      DateTime.compare(now, opens_at) == :lt ->
        {:error, :check_in_not_open}

      DateTime.compare(now, closes_at) != :lt ->
        {:error, :check_in_closed}

      true ->
        :ok
    end
  end
end
