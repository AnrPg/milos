defmodule MilosTraining.Appointments.AppointmentStore do
  @moduledoc false
  @behaviour MilosTraining.Appointments.Ports.AppointmentStore

  alias MilosTraining.Infrastructure.Tenancy.RepoContext

  defp adapter, do: Application.fetch_env!(:milos_training, :appointment_store)

  defp tenant_call(context, function, args) do
    RepoContext.run(context, fn -> apply(adapter(), function, [context | args]) end)
  end

  @impl true
  def create_slot(context, attrs), do: tenant_call(context, :create_slot, [attrs])

  @impl true
  def get_slot(context, id), do: tenant_call(context, :get_slot, [id])

  @impl true
  def list_slots(context, filters), do: tenant_call(context, :list_slots, [filters])

  @impl true
  def cancel_slot(context, id), do: tenant_call(context, :cancel_slot, [id])

  @impl true
  def create_booking(context, attrs, check),
    do: tenant_call(context, :create_booking, [attrs, check])

  @impl true
  def get_booking(context, id), do: tenant_call(context, :get_booking, [id])

  @impl true
  def list_bookings(context, filters), do: tenant_call(context, :list_bookings, [filters])

  @impl true
  def cancel_booking(context, id, late?), do: tenant_call(context, :cancel_booking, [id, late?])

  @impl true
  def record_attendance(context, id, status),
    do: tenant_call(context, :record_attendance, [id, status])
end
