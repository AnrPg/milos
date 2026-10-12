defmodule MilosTrainingWeb.ClassTimerChannel do
  @moduledoc "Live class timer updates for the wall display, the coach remote and members' phones."
  use Phoenix.Channel

  alias MilosTraining.Scheduling
  alias MilosTrainingWeb.TenantChannelContext

  @viewer_roles [:owner, :admin, :coach, :member, :athlete]

  @impl true
  def join("class_timer:" <> slot_id, _payload, socket) do
    with %{organization: %{id: organization_id}} <- socket.assigns[:tenant_context],
         {:ok, context} <- TenantChannelContext.refresh(socket, organization_id),
         true <- context.role in @viewer_roles,
         {:ok, slot_id} <- Ecto.UUID.cast(slot_id),
         %{organization_id: ^organization_id} <- Scheduling.get_slot(context, slot_id) do
      {:ok, assign(socket, :tenant_context, context)}
    else
      _reason -> {:error, %{reason: "unauthorized"}}
    end
  end
end
