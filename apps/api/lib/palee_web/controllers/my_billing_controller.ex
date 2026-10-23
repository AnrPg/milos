defmodule PaleeWeb.MyBillingController do
  @moduledoc """
  Εγώ › Πληρωμές & αποδείξεις: the person's packages, invoices, payments,
  receipts, offers, seasons and referral rewards at every provider they are
  a client of.
  """

  use PaleeWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Palee.Application.MyBilling
  alias PaleeWeb.Schemas.MyBilling, as: S

  action_fallback PaleeWeb.FallbackController

  tags(["Me"])
  security([%{"bearerAuth" => []}])

  operation(:index,
    summary: "Your billing at every gym or coach you are a client of",
    responses: [ok: {"Billing", "application/json", S.response()}]
  )

  def index(conn, _params) do
    with {:ok, billing} <- MyBilling.call(conn.assigns.user_context) do
      json(conn, billing)
    end
  end
end
