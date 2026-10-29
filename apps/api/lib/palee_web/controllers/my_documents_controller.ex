defmodule PaleeWeb.MyDocumentsController do
  @moduledoc """
  Box › Documents for a client (ADR-252): what is still to sign, reading
  and signing the current version (simple electronic signature with
  evidence), the signed documents with their PDF certificates, and the
  client's own health certificate.
  """

  use PaleeWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Guardian.Plug, as: GuardianPlug
  alias Palee.Application.Documents.MyDocuments
  alias PaleeWeb.Schemas.Documents, as: D

  action_fallback PaleeWeb.FallbackController

  tags(["Documents"])
  security([%{"bearerAuth" => []}])

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

  operation(:index,
    summary: "My documents: what is outstanding, offered or signed, and my health certificate",
    responses: [ok: {"My documents", "application/json", D.my_overview()}]
  )

  def index(conn, _params), do: json(conn, MyDocuments.overview(conn.assigns.tenant_context))

  operation(:show,
    summary: "The current text of a document, to read before signing",
    parameters: [D.path_id()],
    responses: [ok: {"Document", "application/json", D.my_document()}]
  )

  def show(conn, %{id: id}) do
    with {:ok, result} <- MyDocuments.document(conn.assigns.tenant_context, id) do
      json(conn, result)
    end
  end

  operation(:sign,
    summary: "Sign the current version (typed name and/or drawn signature)",
    description:
      "Simple electronic signature (eIDAS art. 25): the evidence keeps the SHA-256 of the exact " <>
        "text, the time, the IP address, the device and the account, and a PDF certificate is " <>
        "stored. `version_id` must be the version that was read.",
    parameters: [D.path_id()],
    request_body: D.body(D.sign_body()),
    responses: [created: {"Signature", "application/json", D.one(:signature, D.signature())}]
  )

  def sign(conn, %{id: id}) do
    request = %{
      account: GuardianPlug.current_resource(conn),
      ip_address: conn.remote_ip,
      user_agent: conn |> get_req_header("user-agent") |> List.first()
    }

    with {:ok, result} <-
           MyDocuments.sign(conn.assigns.tenant_context, id, conn.body_params, request) do
      conn |> put_status(:created) |> json(result)
    end
  end

  operation(:signatures,
    summary: "My signatures, newest first",
    responses: [ok: {"Signatures", "application/json", D.signature_page()}]
  )

  def signatures(conn, _params),
    do: json(conn, MyDocuments.signatures(conn.assigns.tenant_context))

  operation(:evidence,
    summary: "A short-lived link to the PDF certificate of my signature",
    parameters: [D.path_id()],
    responses: [ok: {"Certificate", "application/json", D.evidence_link()}]
  )

  def evidence(conn, %{id: id}) do
    with {:ok, result} <- MyDocuments.evidence(conn.assigns.tenant_context, id) do
      json(conn, result)
    end
  end

  operation(:request_health_upload,
    summary: "Upload my health certificate: get a presigned upload",
    request_body: D.body(D.upload_request_body(false)),
    responses: [ok: {"Upload", "application/json", D.upload()}]
  )

  def request_health_upload(conn, _params) do
    with {:ok, upload} <-
           MyDocuments.request_health_upload(conn.assigns.tenant_context, conn.body_params) do
      json(conn, upload)
    end
  end

  operation(:create_health_certificate,
    summary: "Record my uploaded health certificate with its dates",
    request_body: D.body(D.upload_complete_body(false)),
    responses: [
      created: {"Health certificate", "application/json", D.one(:health_certificate, D.certificate())}
    ]
  )

  def create_health_certificate(conn, _params) do
    with {:ok, result} <-
           MyDocuments.complete_health_upload(conn.assigns.tenant_context, conn.body_params) do
      conn |> put_status(:created) |> json(result)
    end
  end

  operation(:health_file,
    summary: "A short-lived link to my health certificate file",
    parameters: [D.path_id()],
    responses: [ok: {"File", "application/json", D.file_link()}]
  )

  def health_file(conn, %{id: id}) do
    with {:ok, result} <- MyDocuments.health_file(conn.assigns.tenant_context, id) do
      json(conn, result)
    end
  end

  operation(:delete_health_certificate,
    summary: "Delete my health certificate and its file",
    parameters: [D.path_id()],
    responses: [
      ok: {"Health certificate", "application/json", D.one(:health_certificate, D.certificate())}
    ]
  )

  def delete_health_certificate(conn, %{id: id}) do
    with {:ok, result} <-
           MyDocuments.delete_health_certificate(conn.assigns.tenant_context, id) do
      json(conn, result)
    end
  end
end
