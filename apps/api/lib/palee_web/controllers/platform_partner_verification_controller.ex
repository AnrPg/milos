defmodule PaleeWeb.PlatformPartnerVerificationController do
  @moduledoc """
  ADR-280 §5, the vendors' console: the Partners check's queue, one request
  with its 5-minute selfie link, and the decision.
  """

  use PaleeWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias OpenApiSpex.{Parameter, Schema}
  alias Palee.Application.PlatformPartnerVerifications
  alias Palee.Partners.Verifications
  alias PaleeWeb.Schemas.PartnerVerification, as: S

  action_fallback PaleeWeb.FallbackController

  tags(["Platform Partners verification"])
  security([%{"bearerAuth" => []}])

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

  @id %Parameter{name: :id, in: :path, required: true, schema: S.uuid()}

  operation(:index,
    summary: "Partners verification requests in a status, default in_review (vendors)",
    parameters: [
      %Parameter{
        name: :status,
        in: :query,
        required: false,
        schema: %Schema{type: :string, enum: Verifications.request_statuses()}
      }
    ],
    responses: [ok: {"Requests", "application/json", S.platform_list()}]
  )

  def index(conn, params) do
    with {:ok, result} <-
           PlatformPartnerVerifications.list(conn.assigns.platform_context, params),
         do: json(conn, result)
  end

  operation(:show,
    summary: "One request: the selfie (5-minute link), its code, the avatar, sponsors (vendors)",
    parameters: [@id],
    responses: [ok: {"Request", "application/json", S.platform_detail()}]
  )

  def show(conn, %{id: id}) do
    with {:ok, result} <- PlatformPartnerVerifications.show(conn.assigns.platform_context, id),
         do: json(conn, result)
  end

  operation(:decide,
    summary: "Approve or reject a request in review; a reason is required to reject (vendors)",
    description: "The selfie is deleted and only the outcome is kept.",
    parameters: [@id],
    request_body: S.body(S.platform_decision_request()),
    responses: [ok: {"Decision", "application/json", S.platform_decision()}]
  )

  def decide(conn, %{id: id}) do
    with {:ok, result} <-
           PlatformPartnerVerifications.decide(
             conn.assigns.platform_context,
             id,
             conn.body_params
           ),
         do: json(conn, result)
  end
end
