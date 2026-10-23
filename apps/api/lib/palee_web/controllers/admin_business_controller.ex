defmodule PaleeWeb.AdminBusinessController do
  @moduledoc """
  ADR-184, for the owners and admins of a business: its activation state, the
  floating button's demo data, and the request to activate it.
  """

  use PaleeWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Palee.Application.{BusinessRequests, DemoData}
  alias PaleeWeb.BusinessAccountJSON
  alias PaleeWeb.Schemas.BusinessAccounts, as: S

  action_fallback PaleeWeb.FallbackController

  tags(["Admin business"])
  security([%{"bearerAuth" => []}])

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

  operation(:show,
    summary: "Activation state and the sections holding demo data",
    responses: [ok: {"Status", "application/json", S.demo_status()}]
  )

  def show(conn, _params) do
    context = conn.assigns.tenant_context

    with {:ok, status} <- DemoData.status(context) do
      json(
        conn,
        BusinessAccountJSON.demo_status(status, BusinessRequests.activation_request(context))
      )
    end
  end

  operation(:seed,
    summary: "Fill a screen's section (or all) with demo data (demo mode only)",
    request_body: S.seed_body(),
    responses: [ok: {"Status", "application/json", S.demo_status()}]
  )

  def seed(conn, _params) do
    context = conn.assigns.tenant_context

    with {:ok, status} <- DemoData.seed(context, conn.body_params.section) do
      json(
        conn,
        BusinessAccountJSON.demo_status(status, BusinessRequests.activation_request(context))
      )
    end
  end

  operation(:remove,
    summary: "Remove every demo row (demo mode only)",
    responses: [ok: {"Status", "application/json", S.demo_status()}]
  )

  def remove(conn, _params) do
    context = conn.assigns.tenant_context

    with {:ok, status} <- DemoData.remove(context) do
      json(
        conn,
        BusinessAccountJSON.demo_status(status, BusinessRequests.activation_request(context))
      )
    end
  end

  operation(:request_activation,
    summary: "Ask the platform team to activate this business (owners)",
    request_body: S.activation_request_body(),
    responses: [created: {"Request", "application/json", S.request()}]
  )

  def request_activation(conn, _params) do
    with {:ok, request} <-
           BusinessRequests.request_activation(conn.assigns.tenant_context, conn.body_params) do
      conn |> put_status(:created) |> json(BusinessAccountJSON.request(request))
    end
  end
end
