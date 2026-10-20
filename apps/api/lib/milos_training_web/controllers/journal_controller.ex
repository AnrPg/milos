defmodule MilosTrainingWeb.JournalController do
  @moduledoc """
  Ημερολόγιο (ADR-139): the member's feed across every entry kind, moving an
  entry on the visibility ladder (with Ζητάω απάντηση), Σημείωση notes, and a
  coach's read of one client's journal.
  """

  use MilosTrainingWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias MilosTraining.Application.{
    GetClientJournal,
    GetJournalFeed,
    JournalNotes,
    SetJournalVisibility
  }

  alias MilosTrainingWeb.Schemas.JournalFeed, as: Schemas
  alias OpenApiSpex.{MediaType, Parameter, RequestBody, Schema}

  action_fallback MilosTrainingWeb.FallbackController

  tags(["Journal"])
  security([%{"bearerAuth" => []}])

  plug(OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true)

  @page_params [
    %Parameter{
      name: :cursor,
      in: :query,
      required: false,
      description: "`next_cursor` of the previous page",
      schema: %Schema{type: :string}
    },
    %Parameter{
      name: :kinds,
      in: :query,
      required: false,
      description: "Comma-separated kinds to list (all when absent)",
      schema: %Schema{type: :string}
    },
    %Parameter{
      name: :limit,
      in: :query,
      required: false,
      schema: %Schema{type: :integer, minimum: 1, maximum: 100}
    }
  ]

  @id_param %Parameter{
    name: :id,
    in: :path,
    required: true,
    schema: %Schema{type: :string, format: :uuid}
  }

  operation(:index,
    summary: "Your journal: every entry kind, newest first",
    parameters: @page_params,
    responses: [ok: {"Feed page", "application/json", Schemas.page()}]
  )

  def index(conn, params) do
    with {:ok, page} <- GetJournalFeed.call(conn.assigns.user_context, page_params(params)) do
      json(conn, page)
    end
  end

  operation(:set_visibility,
    summary: "Move one of your entries on the visibility ladder",
    parameters: [
      %Parameter{
        name: :kind,
        in: :path,
        required: true,
        schema: %Schema{type: :string, enum: Schemas.movable_kinds()}
      },
      @id_param
    ],
    request_body: %RequestBody{
      required: true,
      content: %{"application/json" => %MediaType{schema: Schemas.visibility_request()}}
    },
    responses: [
      ok: {"New rung", "application/json", Schemas.visibility_response()},
      not_found: {"Entry not found", "application/json", %Schema{type: :object}},
      unprocessable_entity: {"Rung not allowed", "application/json", %Schema{type: :object}}
    ]
  )

  def set_visibility(conn, %{kind: kind, id: id}) do
    with {:ok, result} <-
           SetJournalVisibility.call(conn.assigns.user_context, kind, id, body_params(conn)) do
      json(conn, result)
    end
  end

  operation(:create_note,
    summary: "Write a Σημείωση",
    request_body: %RequestBody{
      required: true,
      content: %{"application/json" => %MediaType{schema: Schemas.note_create_request()}}
    },
    responses: [created: {"Note", "application/json", Schemas.note_response()}]
  )

  def create_note(conn, _params) do
    with {:ok, note} <- JournalNotes.create(conn.assigns.user_context, body_params(conn)) do
      conn
      |> put_status(:created)
      |> json(%{note: note})
    end
  end

  operation(:update_note,
    summary: "Edit one of your notes",
    parameters: [@id_param],
    request_body: %RequestBody{
      required: true,
      content: %{"application/json" => %MediaType{schema: Schemas.note_update_request()}}
    },
    responses: [ok: {"Note", "application/json", Schemas.note_response()}]
  )

  def update_note(conn, %{id: id}) do
    with {:ok, note} <- JournalNotes.update(conn.assigns.user_context, id, body_params(conn)) do
      json(conn, %{note: note})
    end
  end

  operation(:delete_note,
    summary: "Delete one of your notes",
    parameters: [@id_param],
    responses: [no_content: "Deleted"]
  )

  def delete_note(conn, %{id: id}) do
    with :ok <- JournalNotes.delete(conn.assigns.user_context, id) do
      send_resp(conn, :no_content, "")
    end
  end

  operation(:client_journal,
    summary: "A client's journal as their coach may read it (audited)",
    parameters: [
      %Parameter{
        name: :user_id,
        in: :path,
        required: true,
        schema: %Schema{type: :string, format: :uuid}
      }
      | @page_params
    ],
    responses: [ok: {"Feed page", "application/json", Schemas.page()}]
  )

  def client_journal(conn, %{user_id: user_id} = params) do
    with {:ok, page} <-
           GetClientJournal.call(conn.assigns.tenant_context, user_id, page_params(params)) do
      json(conn, page)
    end
  end

  defp page_params(params), do: Map.take(params, [:cursor, :kinds, :limit])

  # CastAndValidate atomizes body keys; the application reads string keys.
  defp body_params(conn), do: conn.body_params |> Jason.encode!() |> Jason.decode!()
end
