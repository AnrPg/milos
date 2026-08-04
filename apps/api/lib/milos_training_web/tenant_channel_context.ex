defmodule MilosTrainingWeb.TenantChannelContext do
  alias MilosTraining.Application.ResolveTenantContext

  def refresh(socket, organization_id) do
    with %{organization: organization} <- socket.assigns[:tenant_context],
         ^organization_id <- organization.id,
         {:ok, context} <-
           ResolveTenantContext.call(socket.assigns.current_user, organization.slug, %{
             transport: :channel
           }) do
      {:ok, context}
    else
      _reason -> {:error, :forbidden}
    end
  end
end
