defmodule PaleeWeb.PlatformFiscalConnectionsController do
  @moduledoc """
  Vendor console › a box's fiscal connections (ADR-273). Setting up
  fiskaly (the E-INVOICE System, the Peppol registration) can be done by
  the box's owner or by the Palee team; the Palee team chooses per box
  (`managed_by`) and can fill or replace any of the box's connections.
  Every change is written to the vendors' audit log and the box's fiscal
  journal; credentials are never returned, logged, journaled or exported.
  """

  use PaleeWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias OpenApiSpex.{Parameter, Schema}
  alias Palee.Application.Fiscal.FiscalConnections
  alias PaleeWeb.Schemas.Fiscal, as: F
  alias PaleeWeb.Schemas.FiscalConnections, as: FC

  action_fallback PaleeWeb.FallbackController

  tags(["Platform Organizations"])
  security([%{"bearerAuth" => []}])

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

  @organization_id %Parameter{
    name: :id,
    in: :path,
    required: true,
    schema: %Schema{type: :string, format: :uuid}
  }

  @kind %Parameter{
    name: :kind,
    in: :path,
    required: true,
    schema: %Schema{type: :string, enum: FC.kinds()}
  }

  operation(:show,
    summary: "A box's fiscal connections and who manages them (never a credential)",
    parameters: [@organization_id],
    responses: [ok: {"Connections", "application/json", FC.overview()}]
  )

  def show(conn, %{id: id}) do
    with {:ok, overview} <- FiscalConnections.platform_overview(conn.assigns.platform_context, id) do
      json(conn, overview)
    end
  end

  operation(:managed_by,
    summary: "Choose who manages a box's fiscal connections: its owner or the Palee team",
    parameters: [@organization_id],
    request_body: F.body(FC.managed_by_body()),
    responses: [ok: {"Connections", "application/json", FC.overview()}]
  )

  def managed_by(conn, %{id: id}) do
    with {:ok, overview} <-
           FiscalConnections.set_managed_by(conn.assigns.platform_context, id, conn.body_params) do
      json(conn, overview)
    end
  end

  operation(:save,
    summary: "Fill or replace one of a box's fiscal connections (Palee team)",
    description:
      "Takes the same fields as the box's own save for that connection; saved secrets are " <>
        "kept when none are sent. The connection is then checked. Audited without any secret.",
    parameters: [@organization_id, @kind],
    request_body: F.body(FC.platform_save_body()),
    responses: [ok: {"Connection", "application/json", FC.any_result()}]
  )

  def save(conn, %{id: id, kind: kind}) do
    with {:ok, result} <-
           FiscalConnections.save(conn.assigns.platform_context, id, kind, conn.body_params) do
      json(conn, result)
    end
  end

  operation(:check,
    summary: "«Δοκιμή σύνδεσης» of one of a box's fiscal connections (Palee team)",
    parameters: [@organization_id, @kind],
    responses: [ok: {"Check", "application/json", FC.any_result()}]
  )

  def check(conn, %{id: id, kind: kind}) do
    with {:ok, result} <-
           FiscalConnections.platform_check(conn.assigns.platform_context, id, kind) do
      json(conn, result)
    end
  end
end
