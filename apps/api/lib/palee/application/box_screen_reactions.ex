defmodule Palee.Application.BoxScreenReactions do
  @moduledoc """
  Box screens follow the day (ADR-253): bookings, attendance, cancelled
  classes and new results send the box's screens a refresh hint
  (`%{kind, slot_id}`, never who).
  """

  @behaviour Palee.DomainEvents.Handler

  alias Palee.Application.BoxScreens.BoxScreenSignals

  @impl true
  def handle_event(:booking_made, %{organization_id: organization_id} = event),
    do: BoxScreenSignals.hint(organization_id, "booking", event[:scheduled_class_id])

  def handle_event(:booking_cancelled, %{organization_id: organization_id} = event),
    do: BoxScreenSignals.hint(organization_id, "booking", event[:scheduled_class_id])

  def handle_event(:attendance_recorded, %{organization_id: organization_id} = event),
    do: BoxScreenSignals.hint(organization_id, "attendance", event[:scheduled_class_id])

  def handle_event(:class_cancelled, %{organization_id: organization_id} = event),
    do: BoxScreenSignals.hint(organization_id, "class_cancelled", event[:scheduled_class_id])

  def handle_event(:workout_result_recorded, %{organization_id: organization_id} = event),
    do: BoxScreenSignals.hint(organization_id, "result", event[:scheduled_class_id])

  def handle_event(_name, _event), do: :ok
end
