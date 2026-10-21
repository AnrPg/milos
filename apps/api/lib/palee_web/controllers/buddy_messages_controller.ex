defmodule PaleeWeb.BuddyMessagesController do
  @moduledoc """
  The buddy conversation (ADR-160 §2): one thread per buddy link, readable
  only by its two people, whether or not they share a gym. Writing needs an
  active link; an ended link's thread is read-only.
  """

  use PaleeWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Palee.Application.BuddyMessages
  alias PaleeWeb.Schemas.Buddies, as: S
  alias OpenApiSpex.{Parameter, Schema}

  action_fallback PaleeWeb.FallbackController

  tags(["Buddies"])
  security([%{"bearerAuth" => []}])

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

  @id %Parameter{name: :id, in: :path, required: true, schema: S.uuid()}

  operation(:index,
    summary: "The link's conversation, newest first (cursor paging)",
    parameters: [
      @id,
      %Parameter{name: :cursor, in: :query, required: false, schema: %Schema{type: :string}},
      %Parameter{
        name: :limit,
        in: :query,
        required: false,
        schema: %Schema{type: :integer, minimum: 1, maximum: 100}
      }
    ],
    responses: [ok: {"Messages", "application/json", S.message_page()}]
  )

  def index(conn, %{id: id} = params) do
    with {:ok, page} <- BuddyMessages.list(conn.assigns.user_context, id, params),
         do: json(conn, page)
  end

  operation(:create,
    summary: "Write to your buddy (the link must be active)",
    parameters: [@id],
    request_body: S.body(S.message_request()),
    responses: [created: {"Message", "application/json", S.message_response()}]
  )

  def create(conn, %{id: id}) do
    with {:ok, message} <- BuddyMessages.post(conn.assigns.user_context, id, conn.body_params) do
      conn |> put_status(:created) |> json(%{message: message})
    end
  end

  operation(:read,
    summary: "Mark the other person's messages read",
    parameters: [@id],
    responses: [ok: {"Read", "application/json", S.messages_read_response()}]
  )

  def read(conn, %{id: id}) do
    with {:ok, result} <- BuddyMessages.mark_read(conn.assigns.user_context, id),
         do: json(conn, result)
  end
end
