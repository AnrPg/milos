defmodule PaleeWeb.CheckInChannel do
  @moduledoc """
  Live check-ins of a box for the desk and the door display (ADR-155):
  `checked_in` (first names only), `check_in_undone` and `visitor_scanned`.
  Staff with the `check_in` capability only.
  """

  use Phoenix.Channel

  alias Palee.Organizations.Domain.TenantAuthorization
  alias PaleeWeb.TenantChannelContext

  @impl true
  def join("check_in:" <> organization_id, _payload, socket) do
    with true <- organization_id != "",
         {:ok, context} <- TenantChannelContext.refresh(socket, organization_id),
         true <- TenantAuthorization.can?(context, :check_in) do
      {:ok, assign(socket, :tenant_context, context)}
    else
      _reason -> {:error, %{reason: "unauthorized"}}
    end
  end
end
