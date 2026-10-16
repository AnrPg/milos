defmodule MilosTrainingWeb.CoachNotesController do
  @moduledoc "Private coach notes and who read them (ADR-101)."

  use MilosTrainingWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias MilosTraining.Application.CoachNotes
  alias MilosTraining.Organizations
  alias MilosTrainingWeb.Schemas.CoachNotes, as: S
  alias OpenApiSpex.{Parameter, Schema}

  action_fallback MilosTrainingWeb.FallbackController

  tags(["Coach notes"])
  security([%{"bearerAuth" => []}])

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

  @id %Parameter{name: :id, in: :path, required: true, schema: S.uuid()}
  @user_id %Parameter{name: :user_id, in: :path, required: true, schema: S.uuid()}

  operation(:index,
    summary: "Private notes about a client that you may read (reads are logged)",
    parameters: [@user_id],
    responses: [ok: {"Notes", "application/json", S.many(:notes, S.note())}]
  )

  def index(conn, %{user_id: user_id}) do
    with {:ok, notes} <- CoachNotes.list(conn.assigns.tenant_context, user_id) do
      json(conn, %{notes: notes})
    end
  end

  operation(:create,
    summary:
      "Write a private note about one of your clients, optionally about one thing of theirs",
    parameters: [@user_id],
    request_body: S.body(S.create_schema()),
    responses: [created: {"Note", "application/json", S.one(:note, S.note())}]
  )

  def create(conn, %{user_id: user_id}) do
    with {:ok, note} <-
           CoachNotes.create(
             conn.assigns.tenant_context,
             user_id,
             conn.body_params.body,
             subject(conn.body_params)
           ) do
      conn |> put_status(:created) |> json(%{note: note})
    end
  end

  operation(:update,
    summary: "Edit your note",
    parameters: [@id],
    request_body: S.body(S.body_schema()),
    responses: [ok: {"Note", "application/json", S.one(:note, S.note())}]
  )

  def update(conn, %{id: id}) do
    with {:ok, note} <- CoachNotes.update(conn.assigns.tenant_context, id, conn.body_params.body) do
      json(conn, %{note: note})
    end
  end

  operation(:delete,
    summary: "Delete your note",
    parameters: [@id],
    responses: [no_content: {"Deleted", "application/json", %Schema{type: :object}}]
  )

  def delete(conn, %{id: id}) do
    with :ok <- CoachNotes.delete(conn.assigns.tenant_context, id) do
      send_resp(conn, :no_content, "")
    end
  end

  operation(:reads,
    summary: "Who read your notes, and when",
    responses: [ok: {"Reads", "application/json", S.many(:reads, S.read())}]
  )

  def reads(conn, _params) do
    with {:ok, reads} <- CoachNotes.reads(conn.assigns.tenant_context) do
      json(conn, %{reads: reads})
    end
  end

  operation(:visibility,
    summary: "Let admins read your notes or not (owners always can)",
    request_body:
      S.body(%Schema{
        type: :object,
        properties: %{visible_to_admins: %Schema{type: :boolean}},
        required: [:visible_to_admins]
      }),
    responses: [
      ok:
        {"Visibility", "application/json",
         %Schema{
           type: :object,
           properties: %{visible_to_admins: %Schema{type: :boolean}},
           required: [:visible_to_admins]
         }}
    ]
  )

  def visibility(conn, _params) do
    visible = conn.body_params.visible_to_admins

    with {:ok, membership} <-
           Organizations.set_notes_visibility(conn.assigns.tenant_context, visible) do
      json(conn, %{visible_to_admins: membership.notes_visible_to_admins})
    end
  end

  # Half a subject reaches the changeset, which rejects it.
  defp subject(params) do
    kind = Map.get(params, :subject_kind)
    id = Map.get(params, :subject_id)
    if kind || id, do: %{kind: kind, id: id}
  end
end
