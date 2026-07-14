defmodule MilosTraining.Application.DeleteScheduledSlot do
  alias MilosTraining.Scheduling

  def call(id) do
    with :ok <- Scheduling.delete_slot(id) do
      broadcast_slot_deleted(id)
      :ok
    end
  end

  defp broadcast_slot_deleted(slot_id) do
    Phoenix.PubSub.broadcast(
      MilosTraining.PubSub,
      "schedule:slot_deleted",
      {:schedule_slot_deleted, %{slot_id: slot_id}}
    )
  end
end
