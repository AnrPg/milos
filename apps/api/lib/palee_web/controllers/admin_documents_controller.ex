defmodule PaleeWeb.AdminDocumentsController do
  @moduledoc """
  Staff › Documents (ADR-252): documents with immutable versions, which
  are mandatory, signature requests (one client or in bulk), signatures
  with their PDF certificates, a client's documents, settings and the
  audit log.
  """

  use PaleeWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias OpenApiSpex.Schema
  alias Palee.Application.Documents.DocumentsAdmin
  alias PaleeWeb.Schemas.Documents, as: D

  action_fallback PaleeWeb.FallbackController

  tags(["Documents"])
  security([%{"bearerAuth" => []}])

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

  operation(:index,
    summary: "The box's documents, active first",
    parameters: [
      D.query(:status, %Schema{type: :string, enum: ["active", "archived"]}),
      D.query(:requirement, %Schema{type: :string, enum: ["mandatory", "optional"]})
    ],
    responses: [ok: {"Documents", "application/json", D.templates()}]
  )

  def index(conn, params),
    do: json(conn, DocumentsAdmin.list_templates(conn.assigns.tenant_context, params))

  operation(:starters,
    summary: "Ready-made drafts to start from (always marked for legal review)",
    parameters: [D.query(:language, %Schema{type: :string, enum: ["el", "en"]})],
    responses: [ok: {"Drafts", "application/json", D.starters()}]
  )

  def starters(conn, params), do: json(conn, DocumentsAdmin.starters(params))

  operation(:create,
    summary: "Create a document with its first version",
    request_body: D.body(D.template_body()),
    responses: [created: {"Document", "application/json", D.published()}]
  )

  def create(conn, _params) do
    with {:ok, result} <-
           DocumentsAdmin.create_template(conn.assigns.tenant_context, conn.body_params) do
      conn |> put_status(:created) |> json(result)
    end
  end

  operation(:show,
    summary: "A document with its versions and the current text",
    parameters: [D.path_id()],
    responses: [ok: {"Document", "application/json", D.template_detail()}]
  )

  def show(conn, %{id: id}) do
    with {:ok, result} <- DocumentsAdmin.get_template(conn.assigns.tenant_context, id) do
      json(conn, result)
    end
  end

  operation(:version,
    summary: "One version's text",
    parameters: [D.path_id(), D.path_id(:version_id)],
    responses: [ok: {"Version", "application/json", D.one(:version, D.version())}]
  )

  def version(conn, %{id: id, version_id: version_id}) do
    with {:ok, result} <- DocumentsAdmin.get_version(conn.assigns.tenant_context, id, version_id) do
      json(conn, result)
    end
  end

  operation(:publish,
    summary: "Publish a new version (major: everyone signs again; minor: signatures still count)",
    parameters: [D.path_id()],
    request_body: D.body(D.version_body()),
    responses: [created: {"Version", "application/json", D.published()}]
  )

  def publish(conn, %{id: id}) do
    with {:ok, result} <-
           DocumentsAdmin.publish_version(conn.assigns.tenant_context, id, conn.body_params) do
      conn |> put_status(:created) |> json(result)
    end
  end

  operation(:set_requirement,
    summary: "Mark a document mandatory (blocks booking) or optional (only offered)",
    parameters: [D.path_id()],
    request_body: D.body(D.requirement_body()),
    responses: [ok: {"Document", "application/json", D.one(:template, D.template())}]
  )

  def set_requirement(conn, %{id: id}) do
    with {:ok, result} <-
           DocumentsAdmin.set_requirement(conn.assigns.tenant_context, id, conn.body_params) do
      json(conn, result)
    end
  end

  operation(:archive,
    summary: "Archive a document: no longer offered, required or requested",
    parameters: [D.path_id()],
    responses: [ok: {"Document", "application/json", D.one(:template, D.template())}]
  )

  def archive(conn, %{id: id}) do
    with {:ok, result} <- DocumentsAdmin.archive_template(conn.assigns.tenant_context, id) do
      json(conn, result)
    end
  end

  operation(:request,
    summary: "Ask one client, every client, a role or a package's holders to sign",
    description:
      "Clients who already signed the required version or have a pending request are skipped. " <>
        "Each new request notifies its client.",
    parameters: [D.path_id()],
    request_body: D.body(D.request_body()),
    responses: [created: {"Requests", "application/json", D.request_result()}]
  )

  def request(conn, %{id: id}) do
    with {:ok, result} <-
           DocumentsAdmin.request_signatures(conn.assigns.tenant_context, id, conn.body_params) do
      conn |> put_status(:created) |> json(result)
    end
  end

  operation(:requests,
    summary: "Signature requests, newest first",
    parameters:
      [
        D.query(:status, %Schema{type: :string, enum: ["pending", "signed", "cancelled"]}),
        D.query(:template_id, D.uuid()),
        D.query(:user_id, D.uuid()),
        D.query(:batch_id, D.uuid())
      ] ++ D.paging(),
    responses: [ok: {"Requests", "application/json", D.request_page()}]
  )

  def requests(conn, params),
    do: json(conn, DocumentsAdmin.list_requests(conn.assigns.tenant_context, params))

  operation(:cancel_request,
    summary: "Cancel a pending request",
    parameters: [D.path_id()],
    responses: [ok: {"Request", "application/json", D.one(:request, D.request())}]
  )

  def cancel_request(conn, %{id: id}) do
    with {:ok, result} <- DocumentsAdmin.cancel_request(conn.assigns.tenant_context, id) do
      json(conn, result)
    end
  end

  operation(:signatures,
    summary: "Signatures with their evidence, newest first",
    parameters: [D.query(:template_id, D.uuid()), D.query(:user_id, D.uuid())] ++ D.paging(),
    responses: [ok: {"Signatures", "application/json", D.signature_page()}]
  )

  def signatures(conn, params),
    do: json(conn, DocumentsAdmin.list_signatures(conn.assigns.tenant_context, params))

  operation(:evidence,
    summary: "A short-lived link to a signature's PDF certificate (audited)",
    parameters: [D.path_id()],
    responses: [ok: {"Certificate", "application/json", D.evidence_link()}]
  )

  def evidence(conn, %{id: id}) do
    with {:ok, result} <- DocumentsAdmin.evidence(conn.assigns.tenant_context, id) do
      json(conn, result)
    end
  end

  operation(:member,
    summary: "A client's documents, signatures and health certificate status",
    parameters: [D.path_id(:user_id)],
    responses: [ok: {"Client documents", "application/json", D.member()}]
  )

  def member(conn, %{user_id: user_id}) do
    with {:ok, result} <- DocumentsAdmin.member(conn.assigns.tenant_context, user_id) do
      json(conn, result)
    end
  end

  operation(:settings,
    summary: "The box's document rules (booking gate, health certificates)",
    responses: [ok: {"Settings", "application/json", D.one(:settings, D.settings())}]
  )

  def settings(conn, _params),
    do: json(conn, DocumentsAdmin.settings(conn.assigns.tenant_context))

  operation(:save_settings,
    summary: "Change the box's document rules (audited)",
    request_body: D.body(D.settings_body()),
    responses: [ok: {"Settings", "application/json", D.one(:settings, D.settings())}]
  )

  def save_settings(conn, _params) do
    with {:ok, result} <-
           DocumentsAdmin.save_settings(conn.assigns.tenant_context, conn.body_params) do
      json(conn, result)
    end
  end

  operation(:audit,
    summary: "The documents audit log, newest first",
    parameters:
      [D.query(:subject_id, D.uuid()), D.query(:action, %Schema{type: :string})] ++
        D.paging(),
    responses: [ok: {"Audit events", "application/json", D.events()}]
  )

  def audit(conn, params),
    do: json(conn, DocumentsAdmin.audit_events(conn.assigns.tenant_context, params))
end
