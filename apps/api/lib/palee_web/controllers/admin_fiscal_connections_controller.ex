defmodule PaleeWeb.AdminFiscalConnectionsController do
  @moduledoc """
  Staff › Settings › Στοιχεία τιμολόγησης › «Συνδέσεις» (ADR-273, mockup
  p3): the connections the box's country asks for, each with its status
  and the result of its last check, and «Δοκιμή σύνδεσης». Each
  connection is still saved through its own endpoint.
  """

  use PaleeWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias OpenApiSpex.Schema
  alias Palee.Application.Fiscal.FiscalConnections
  alias PaleeWeb.Schemas.FiscalConnections, as: FC

  action_fallback PaleeWeb.FallbackController

  tags(["Fiscal"])
  security([%{"bearerAuth" => []}])

  # On top of the per-connection interval (10 minutes for the AADE
  # registry, whose check spends one of the business's look-ups).
  plug PaleeWeb.Plugs.RateLimit,
       [max: 10, interval: 60_000, bucket: "fiscal-connection-check"] when action == :check

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

  operation(:index,
    summary: "The box's fiscal connections: only those its country asks for (never a credential)",
    responses: [ok: {"Connections", "application/json", FC.overview()}]
  )

  def index(conn, _params),
    do: json(conn, FiscalConnections.overview(conn.assigns.tenant_context))

  operation(:check,
    summary: "«Δοκιμή σύνδεσης»: ask the provider whether the saved connection works",
    description:
      "Nothing is sent or signed. myDATA: a harmless request with the business's user and " <>
        "key; AADE registry: a look-up of the business's own ΑΦΜ (one call of its quota, at " <>
        "most every 10 minutes); fiskaly: sign in and read the unit or System Palee uses. A " <>
        "refusal marks the connection invalid (`check.result = invalid`, with `error_code`); " <>
        "a provider that cannot be reached changes nothing (`unreachable`). Errors: " <>
        "`unknown_connection`, `connection_not_found`, `check_too_soon` (429).",
    parameters: [
      kind: [
        in: :path,
        type: %Schema{type: :string, enum: FC.kinds()},
        required: true,
        description: "Which connection"
      ]
    ],
    responses: [ok: {"Check", "application/json", FC.any_result()}]
  )

  def check(conn, %{kind: kind}) do
    with {:ok, result} <- FiscalConnections.check(conn.assigns.tenant_context, kind) do
      json(conn, result)
    end
  end
end
