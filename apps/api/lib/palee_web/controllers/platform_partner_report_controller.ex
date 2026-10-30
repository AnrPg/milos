defmodule PaleeWeb.PlatformPartnerReportController do
  @moduledoc """
  ADR-280, the platform console «Αναφορές Συναθλητών»: the Palee team's
  queue of Partners reports and its decisions (suspend or dismiss).
  """

  use PaleeWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias OpenApiSpex.{Parameter, Schema}
  alias Palee.Application.Partners
  alias PaleeWeb.Schemas.Partners, as: S

  action_fallback PaleeWeb.FallbackController

  tags(["Platform partner reports"])
  security([%{"bearerAuth" => []}])

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

  operation(:index,
    summary: "Partners reports by status, newest first (vendors)",
    parameters: [
      %Parameter{
        name: :status,
        in: :query,
        required: false,
        description: "Default open",
        schema: %Schema{type: :string, enum: Palee.Partners.report_statuses()}
      }
    ],
    responses: [ok: {"Reports", "application/json", S.platform_reports()}]
  )

  def index(conn, params) do
    with {:ok, result} <-
           Partners.platform_reports(conn.assigns.platform_context, %{
             "status" => Map.get(params, :status)
           }),
         do: json(conn, result)
  end

  operation(:decide,
    summary: "Suspend the reported person or dismiss, for every open report on them (vendors)",
    parameters: [%Parameter{name: :id, in: :path, required: true, schema: S.uuid()}],
    request_body: S.body(S.report_decision_request()),
    responses: [ok: {"Decision", "application/json", S.report_decision_response()}]
  )

  def decide(conn, %{id: id}) do
    with {:ok, result} <-
           Partners.decide_report(conn.assigns.platform_context, id, conn.body_params),
         do: json(conn, result)
  end
end
