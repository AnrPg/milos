defmodule MilosTrainingWeb.ScheduleChannel do
  use Phoenix.Channel

  @impl true
  def join("org:" <> topic_suffix, _payload, socket) do
    with [organization_id, "schedule"] <- String.split(topic_suffix, ":", parts: 2),
         %{organization_id: ^organization_id, role: role} <- socket.assigns[:tenant_context],
         true <- role in [:owner, :admin, :coach, :member, :athlete] do
      {:ok, socket}
    else
      _reason -> {:error, %{reason: "unauthorized"}}
    end
  end
end
