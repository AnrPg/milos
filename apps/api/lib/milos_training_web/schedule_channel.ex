defmodule MilosTrainingWeb.ScheduleChannel do
  use Phoenix.Channel

  alias MilosTrainingWeb.TenantChannelContext

  @impl true
  def join("schedule:" <> organization_id, _payload, socket) do
    with true <- organization_id != "",
         {:ok, context} <- TenantChannelContext.refresh(socket, organization_id),
         %{role: role} <- context,
         true <- role in [:owner, :admin, :coach, :member, :athlete] do
      {:ok, assign(socket, :tenant_context, context)}
    else
      _reason -> {:error, %{reason: "unauthorized"}}
    end
  end
end
