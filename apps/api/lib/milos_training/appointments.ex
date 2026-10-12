defmodule MilosTraining.Appointments do
  @moduledoc """
  Appointments context (ADR-098): coach-published PT session and assessment
  slots and the clients booked into them. Bookings that use package units go
  through `Application.BookAppointment` and friends.
  """

  alias MilosTraining.Appointments.AppointmentStore

  def create_slot(context, attrs), do: AppointmentStore.create_slot(context, attrs)
  def get_slot(context, id), do: AppointmentStore.get_slot(context, id)
  def list_slots(context, filters \\ %{}), do: AppointmentStore.list_slots(context, filters)
  def cancel_slot(context, id), do: AppointmentStore.cancel_slot(context, id)

  def create_booking(context, attrs, check),
    do: AppointmentStore.create_booking(context, attrs, check)

  def get_booking(context, id), do: AppointmentStore.get_booking(context, id)
  def list_bookings(context, filters \\ %{}), do: AppointmentStore.list_bookings(context, filters)
  def cancel_booking(context, id, late?), do: AppointmentStore.cancel_booking(context, id, late?)

  def record_attendance(context, id, status),
    do: AppointmentStore.record_attendance(context, id, status)
end
