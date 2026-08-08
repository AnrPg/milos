defmodule MilosTraining.Application.DeleteScheduledSlot do
  alias MilosTraining.Application.ScheduleRealtime
  alias MilosTraining.Scheduling

  def call(context, id) do
    with :ok <- Scheduling.delete_slot(context, id) do
      broadcast_slot_deleted(context.organization_id, id)
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
