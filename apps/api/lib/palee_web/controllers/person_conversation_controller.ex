defmodule PaleeWeb.PersonConversationController do
  @moduledoc """
  Person-to-person conversations (ADR-193 §3): one per pair of people,
  account-scoped, with an inbox and message requests. No gym is needed.
  """

  use PaleeWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Palee.Application.PersonConversations
  alias PaleeWeb.Schemas.Conversations, as: S
  alias OpenApiSpex.{Parameter, Schema}

  action_fallback PaleeWeb.FallbackController

  tags(["Conversations"])
  security([%{"bearerAuth" => []}])

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

  @id %Parameter{name: :id, in: :path, required: true, schema: S.uuid()}
  @cursor %Parameter{name: :cursor, in: :query, required: false, schema: %Schema{type: :string}}
  @limit %Parameter{
    name: :limit,
    in: :query,
    required: false,
    schema: %Schema{type: :integer, minimum: 1, maximum: 100}
  }

  operation(:index,
    summary: "Your conversations in the inbox (default) or in message requests, latest first",
    parameters: [
      %Parameter{name: :folder, in: :query, required: false, schema: S.folder()},
      @cursor,
      @limit
    ],
    responses: [ok: {"Conversations", "application/json", S.conversation_page()}]
  )

  def index(conn, params) do
    with {:ok, page} <- PersonConversations.list(conn.assigns.user_context, params),
         do: json(conn, page)
  end

  operation(:unread_count,
    summary: "How many conversations hold unread messages, in the inbox and in requests",
    responses: [ok: {"Counts", "application/json", S.unread_count_response()}]
  )

  def unread_count(conn, _params) do
    with {:ok, counts} <- PersonConversations.unread_count(conn.assigns.user_context),
         do: json(conn, counts)
  end

  operation(:create,
    summary: "Open (or find) your conversation with a person",
    request_body: S.body(S.open_request()),
    responses: [ok: {"Conversation", "application/json", S.conversation_response()}]
  )

  def create(conn, _params) do
    with {:ok, conversation} <-
           PersonConversations.open(conn.assigns.user_context, conn.body_params.person_id),
         do: json(conn, %{conversation: conversation})
  end

  operation(:show,
    summary: "One conversation as you see it",
    parameters: [@id],
    responses: [ok: {"Conversation", "application/json", S.conversation_response()}]
  )

  def show(conn, %{id: id}) do
    with {:ok, conversation} <- PersonConversations.show(conn.assigns.user_context, id),
         do: json(conn, %{conversation: conversation})
  end

  operation(:messages,
    summary: "The conversation's messages, newest first (cursor paging)",
    parameters: [@id, @cursor, @limit],
    responses: [ok: {"Messages", "application/json", S.message_page()}]
  )

  def messages(conn, %{id: id} = params) do
    with {:ok, page} <- PersonConversations.messages(conn.assigns.user_context, id, params),
         do: json(conn, page)
  end

  operation(:send_message,
    summary: "Write a message (a retry with the same client_operation_id is answered once)",
    parameters: [@id],
    request_body: S.body(S.message_request()),
    responses: [created: {"Message", "application/json", S.message_response()}]
  )

  def send_message(conn, %{id: id}) do
    with {:ok, message} <-
           PersonConversations.post(conn.assigns.user_context, id, conn.body_params) do
      conn |> put_status(:created) |> json(%{message: message})
    end
  end

  operation(:read,
    summary: "Mark the conversation read up to now",
    parameters: [@id],
    responses: [ok: {"Conversation", "application/json", S.conversation_response()}]
  )

  def read(conn, %{id: id}) do
    with {:ok, conversation} <- PersonConversations.read(conn.assigns.user_context, id),
         do: json(conn, %{conversation: conversation})
  end

  operation(:accept,
    summary: "Accept a message request (it moves to the inbox)",
    parameters: [@id],
    responses: [ok: {"Conversation", "application/json", S.conversation_response()}]
  )

  def accept(conn, %{id: id}) do
    with {:ok, conversation} <- PersonConversations.accept(conn.assigns.user_context, id),
         do: json(conn, %{conversation: conversation})
  end

  operation(:decline,
    summary: "Decline a message request (you never see it again; the sender is not told)",
    parameters: [@id],
    responses: [no_content: {"Declined", "application/json", %Schema{type: :object}}]
  )

  def decline(conn, %{id: id}) do
    with :ok <- PersonConversations.decline(conn.assigns.user_context, id),
         do: send_resp(conn, :no_content, "")
  end
end
