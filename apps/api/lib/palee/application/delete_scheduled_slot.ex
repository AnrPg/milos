defmodule Palee.Application.DeleteScheduledSlot do
  alias Palee.Application.{ClassLocation, ScheduleRealtime, TrackAnalyticsEvent}
  alias Palee.Scheduling

  def call(context, id) do
    with :ok <- ClassLocation.authorize_class(context, id),
         :ok <- Scheduling.delete_slot(context, id) do
      broadcast_slot_deleted(context.organization_id, id)

      Palee.DomainEvents.publish(:class_cancelled, %{
        organization_id: context.organization_id,
        scheduled_class_id: id,
        at: DateTime.utc_now()
      })

      TrackAnalyticsEvent.call("class_slot_cancelled", context, %{id: id})
      :ok
    end
  end

  def call(_id), do: {:error, :organization_context_required}

  defp broadcast_slot_deleted(organization_id, slot_id) do
    ScheduleRealtime.broadcast("slot_deleted", %{
      organization_id: organization_id,
      slot_id: slot_id
    })
  end
end
