defmodule PaleeWeb.AdminHealthCertificatesController do
  @moduledoc """
  Staff › Documents › health certificates (ADR-252, GDPR art. 9). Staff
  who manage health certificates see dates and files (every look is
  audited); coaches with `view_health` see only valid, expired or missing
  for their own clients.
  """

  use PaleeWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias OpenApiSpex.Schema
  alias Palee.Application.Documents.HealthCertificatesAdmin
  alias PaleeWeb.Schemas.Documents, as: D

  action_fallback PaleeWeb.FallbackController

  tags(["Documents"])
  security([%{"bearerAuth" => []}])

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

  operation(:index,
    summary: "Clients with their health certificate status",
    parameters: [
      D.query(:status, %Schema{type: :string, enum: ["missing", "valid", "expiring", "expired"]})
    ],
    responses: [ok: {"Health certificates", "application/json", D.health_rows()}]
  )

  def index(conn, params),
    do: json(conn, HealthCertificatesAdmin.list(conn.assigns.tenant_context, params))

  operation(:client,
    summary: "A client's health certificates, newest first",
    parameters: [D.path_id(:user_id)],
    responses: [ok: {"Health certificates", "application/json", D.client_certificates()}]
  )

  def client(conn, %{user_id: user_id}) do
    with {:ok, result} <- HealthCertificatesAdmin.for_client(conn.assigns.tenant_context, user_id) do
      json(conn, result)
    end
  end

  operation(:request_upload,
    summary: "Upload a client's health certificate: get a presigned upload",
    request_body: D.body(D.upload_request_body(true)),
    responses: [ok: {"Upload", "application/json", D.upload()}]
  )

  def request_upload(conn, _params) do
    with {:ok, upload} <-
           HealthCertificatesAdmin.request_upload(conn.assigns.tenant_context, conn.body_params) do
      json(conn, upload)
    end
  end

  operation(:create,
    summary: "Record an uploaded health certificate with its dates",
    request_body: D.body(D.upload_complete_body(true)),
    responses: [
      created: {"Health certificate", "application/json", D.one(:health_certificate, D.certificate())}
    ]
  )

  def create(conn, _params) do
    with {:ok, result} <-
           HealthCertificatesAdmin.complete_upload(conn.assigns.tenant_context, conn.body_params) do
      conn |> put_status(:created) |> json(result)
    end
  end

  operation(:file,
    summary: "A short-lived link to the certificate file (audited)",
    parameters: [D.path_id()],
    responses: [ok: {"File", "application/json", D.file_link()}]
  )

  def file(conn, %{id: id}) do
    with {:ok, result} <- HealthCertificatesAdmin.download(conn.assigns.tenant_context, id) do
      json(conn, result)
    end
  end

  operation(:delete,
    summary: "Delete a health certificate and its file (audited)",
    parameters: [D.path_id()],
    responses: [
      ok: {"Health certificate", "application/json", D.one(:health_certificate, D.certificate())}
    ]
  )

  def delete(conn, %{id: id}) do
    with {:ok, result} <- HealthCertificatesAdmin.delete(conn.assigns.tenant_context, id) do
      json(conn, result)
    end
  end
end
