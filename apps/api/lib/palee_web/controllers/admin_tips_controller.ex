defmodule PaleeWeb.AdminTipsController do
  @moduledoc "Finance › tips per staff member for a period (ADR-272)."

  use PaleeWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias OpenApiSpex.{Parameter, Schema}
  alias Palee.Application.Payments.TipsSummary
  alias PaleeWeb.Schemas.TerminalPayments, as: T

  action_fallback PaleeWeb.FallbackController

  tags(["Payments"])
  security([%{"bearerAuth" => []}])

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

  operation(:index,
    summary: "Card tips per staff member for a period (default: this month)",
    description:
      "Tips are the staff's, not revenue (ADR-264). Each is attributed to whoever started " <>
        "the payment on their phone, or to the front desk (ADR-272).",
    parameters: [
      %Parameter{name: :from, in: :query, required: false, schema: %Schema{type: :string, format: :date}},
      %Parameter{name: :to, in: :query, required: false, schema: %Schema{type: :string, format: :date}}
    ],
    responses: [ok: {"Tips", "application/json", T.tips()}]
  )

  def index(conn, params) do
    with {:ok, tips} <- TipsSummary.call(conn.assigns.tenant_context, params) do
      json(conn, tips)
    end
  end
end
