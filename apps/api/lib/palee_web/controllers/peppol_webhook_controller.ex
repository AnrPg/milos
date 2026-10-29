defmodule PaleeWeb.PeppolWebhookController do
  @moduledoc """
  ADR-250: notifications from the business's Peppol access point. The URL
  carries the business and a secret token (kept only as a hash); a
  notification only makes the delivery poll of the submissions it names
  due now, and the delivery is then read from the access point.
  """

  use PaleeWeb, :controller

  alias Palee.Application.Fiscal.FiscalEInvoicing

  def create(conn, %{"organization_id" => organization_id, "token" => token} = params) do
    with {:ok, organization_id} <- Ecto.UUID.cast(organization_id),
         :ok <-
           FiscalEInvoicing.webhook(
             %{organization_id: organization_id},
             token,
             Map.drop(params, ["organization_id", "token"])
           ) do
      json(conn, %{ok: true})
    else
      _invalid -> conn |> put_status(:not_found) |> json(%{code: "not_found"})
    end
  end
end
