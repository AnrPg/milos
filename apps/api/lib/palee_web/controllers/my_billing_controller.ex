defmodule PaleeWeb.MyBillingController do
  @moduledoc """
  Εγώ › Πληρωμές & αποδείξεις: the person's packages, invoices, payments,
  receipts, offers, seasons and referral rewards at every provider they are
  a client of.
  """

  use PaleeWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Palee.Application.{MyBilling, MyTransactions}
  alias PaleeWeb.Schemas.MyBilling, as: S
  alias OpenApiSpex.{Parameter, Schema}

  action_fallback PaleeWeb.FallbackController

  tags(["Me"])
  security([%{"bearerAuth" => []}])

  plug(OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true)

  operation(:index,
    summary: "Your billing at every gym or coach you are a client of",
    responses: [ok: {"Billing", "application/json", S.response()}]
  )

  def index(conn, _params) do
    with {:ok, billing} <- MyBilling.call(conn.assigns.user_context) do
      json(conn, billing)
    end
  end

  operation(:transactions,
    summary: "Your complete transaction history, newest first (cursor-paginated)",
    parameters: [
      %Parameter{
        name: :organization_id,
        in: :query,
        required: false,
        description: "One provider; event entries of hosts that are not providers always stay.",
        schema: %Schema{type: :string, format: :uuid}
      },
      %Parameter{
        name: :kind,
        in: :query,
        required: false,
        schema: %Schema{type: :string, enum: S.transaction_kinds()}
      },
      %Parameter{name: :cursor, in: :query, required: false, schema: %Schema{type: :string}},
      %Parameter{
        name: :limit,
        in: :query,
        required: false,
        schema: %Schema{type: :integer, minimum: 1, maximum: 100}
      }
    ],
    responses: [
      ok: {"Transactions", "application/json", S.transactions_response()},
      bad_request: {"Invalid cursor", "application/json", %Schema{type: :object}}
    ]
  )

  def transactions(conn, params) do
    params = Map.take(params, [:organization_id, :kind, :cursor, :limit])

    with {:ok, feed} <- MyTransactions.call(conn.assigns.user_context, params) do
      json(conn, feed)
    end
  end
end
