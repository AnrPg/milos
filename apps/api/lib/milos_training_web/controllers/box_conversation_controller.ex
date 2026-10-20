defmodule MilosTrainingWeb.BoxConversationController do
  @moduledoc "Talking to a box from its page (ADR-144, board 6 Q6)."

  use MilosTrainingWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias MilosTraining.Application.BoxConversation
  alias MilosTrainingWeb.Schemas.Trials, as: S
  alias OpenApiSpex.{Parameter, Schema}

  action_fallback MilosTrainingWeb.FallbackController

  tags(["Box conversations"])
  security([%{"bearerAuth" => []}])

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

  @slug %Parameter{
    name: :slug,
    in: :path,
    required: true,
    description: "The box's slug or one of its former slugs",
    schema: %Schema{type: :string, maxLength: 120}
  }
  @missing [
    not_found: {"No such box or conversation", "application/json", %Schema{type: :object}}
  ]

  operation(:open,
    summary: "Start (or return) your conversation with a box",
    parameters: [@slug],
    responses:
      [
        ok: {"Conversation", "application/json", S.conversation_response()},
        forbidden:
          {"Only members and people who tried a class", "application/json",
           %Schema{type: :object}}
      ] ++ @missing
  )

  def open(conn, %{slug: slug}) do
    with {:ok, conversation} <- BoxConversation.open(account(conn), slug),
         do: json(conn, %{conversation: conversation})
  end

  operation(:show,
    summary: "Your conversation with a box and a page of its messages, newest first",
    parameters: [
      @slug,
      %Parameter{
        name: :before_id,
        in: :query,
        required: false,
        schema: %Schema{type: :string, format: :uuid}
      },
      %Parameter{
        name: :limit,
        in: :query,
        required: false,
        schema: %Schema{type: :integer, minimum: 1, maximum: 100}
      }
    ],
    responses: [ok: {"Conversation", "application/json", S.conversation_response()}] ++ @missing
  )

  def show(conn, %{slug: slug} = params) do
    with {:ok, conversation} <-
           BoxConversation.show(account(conn), slug, Map.take(params, [:before_id, :limit])),
         do: json(conn, %{conversation: conversation})
  end

  operation(:send_message,
    summary: "Write to the box",
    parameters: [@slug],
    request_body: S.body(S.message_request()),
    responses: [created: {"Message", "application/json", S.message_response()}] ++ @missing
  )

  def send_message(conn, %{slug: slug}) do
    with {:ok, message} <- BoxConversation.send(account(conn), slug, conn.body_params) do
      conn |> put_status(:created) |> json(%{message: message})
    end
  end

  operation(:mark_read,
    summary: "Mark the conversation read up to a message",
    parameters: [@slug],
    request_body: S.body(S.read_request()),
    responses: [ok: {"Read", "application/json", %Schema{type: :object}}] ++ @missing
  )

  def mark_read(conn, %{slug: slug}) do
    with {:ok, message_id} <-
           BoxConversation.mark_read(account(conn), slug, conn.body_params.message_id),
         do: json(conn, %{last_read_message_id: message_id})
  end

  operation(:index,
    summary: "The boxes you talk to without being a member, latest first",
    responses: [ok: {"Conversations", "application/json", S.conversations_response()}]
  )

  def index(conn, _params),
    do: json(conn, %{conversations: BoxConversation.list(account(conn))})

  defp account(conn), do: conn.assigns.user_context.account
end
