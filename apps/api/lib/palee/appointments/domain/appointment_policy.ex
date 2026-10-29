defmodule Palee.Appointments.Domain.AppointmentPolicy do
  @moduledoc """
  Pure rules for appointments (ADR-098). PT sessions draw on `pt_sessions`,
  assessments on `assessments`. The package that pays decides the format and
  may name the coach; its session length filters the slots offered.
  """

  def allowance(%{kind: "assessment"}), do: :assessments
  def allowance(_slot), do: :pt_sessions

  @doc "Ledger request for one booking of the slot."
  def entitlement_request(%{kind: "assessment"} = slot),
    do: request(slot, :book_assessments, :assessments)

  def entitlement_request(slot), do: request(slot, :book_pt_sessions, :pt_sessions)

  defp request(slot, capability, allowance) do
    %{
      channel: :personal_training,
      capability: capability,
      allowance: allowance,
      quantity: 1,
      starts_at: slot.starts_at,
      location_id: slot.location_id
    }
  end

  @doc "A slot can take the client when it is open, upcoming and has room."
  def can_book?(slot, active_bookings, user_id, %DateTime{} = now) do
    cond do
      not is_nil(slot.cancelled_at) -> {:error, :appointment_slot_cancelled}
      DateTime.compare(slot.starts_at, now) != :gt -> {:error, :appointment_slot_in_past}
      Enum.any?(active_bookings, &(&1.user_id == user_id)) -> {:error, :already_booked}
      length(active_bookings) >= slot.capacity -> {:error, :appointment_slot_full}
      true -> :ok
    end
  end

  @doc """
  The paying package's terms must allow the slot: a PT package sells one
  format and may name one coach. Assessments only need the allowance.
  """
  def terms_allow?(%{kind: "assessment"}, _terms), do: :ok

  def terms_allow?(slot, terms) do
    cond do
      present?(terms[:pt_format]) and terms[:pt_format] != slot.format ->
        {:error, :appointment_format_not_included}

      present?(terms[:pt_coach_id]) and terms[:pt_coach_id] != slot.coach_id ->
        {:error, :appointment_coach_not_included}

      true ->
        :ok
    end
  end

  @doc "Slots worth offering to a client, given the paying package's terms."
  def offered?(slot, terms) do
    terms_allow?(slot, terms) == :ok and
      (slot.kind == "assessment" or not present?(terms[:pt_session_minutes]) or
         terms[:pt_session_minutes] == slot.duration_minutes)
  end

  def late_cancellation?(_starts_at, _now, cutoff) when cutoff in [nil, 0], do: false

  # ADR-226: the cutoff is in minutes before the appointment.
  def late_cancellation?(%DateTime{} = starts_at, %DateTime{} = now, cutoff_minutes),
    do: DateTime.diff(starts_at, now, :second) < cutoff_minutes * 60

  def can_cancel?(%{status: "booked"}), do: :ok
  def can_cancel?(_booking), do: {:error, :appointment_not_active}

  def can_record_attendance?(%{status: "booked"}), do: :ok
  def can_record_attendance?(_booking), do: {:error, :appointment_not_active}

  defp present?(value), do: value not in [nil, ""]
end
