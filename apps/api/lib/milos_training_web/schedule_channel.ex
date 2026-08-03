defmodule MilosTrainingWeb.ScheduleChannel do
  use Phoenix.Channel

  @impl true
  def join("schedule:" <> organization_id, _payload, socket) do
    with true <- organization_id != "",
         %{organization_id: ^organization_id, role: role} <- socket.assigns[:tenant_context],
         true <- role in [:owner, :admin, :coach, :member, :athlete] do
      {:ok, socket}
    else
      _reason -> {:error, %{reason: "unauthorized"}}
    end
  end
end
