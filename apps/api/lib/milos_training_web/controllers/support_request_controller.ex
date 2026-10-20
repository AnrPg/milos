defmodule MilosTrainingWeb.SupportRequestController do
  @moduledoc """
  «Χρειάζομαι στήριξη» (ADR-160): send to your active buddies (a 5-second
  undo before they are told), see who received and replied, and answer as
  a buddy with a quick reply or your own words.
  """

  use MilosTrainingWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias MilosTraining.Application.SupportRequests
  alias MilosTrainingWeb.Schemas.Buddies, as: S
  alias OpenApiSpex.{Parameter, Schema}

  action_fallback MilosTrainingWeb.FallbackController

  tags(["Buddies"])
  security([%{"bearerAuth" => []}])

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

  @id %Parameter{name: :id, in: :path, required: true, schema: S.uuid()}
  @request {"Support request", "application/json", S.support_request_response()}

  operation(:index,
    summary: "Your recent support requests, or the ones you received",
    parameters: [
      %Parameter{
        name: :role,
        in: :query,
        required: false,
        schema: %Schema{type: :string, enum: ["sent", "received"]}
      }
    ],
    responses: [ok: {"Support requests", "application/json", S.support_request_list()}]
  )

  def index(conn, params) do
    with {:ok, requests} <- SupportRequests.list(conn.assigns.user_context, params),
         do: json(conn, %{support_requests: requests})
  end

  operation(:create,
    summary: "Ask your active buddies for support (optional message; nothing else is shared)",
    request_body: S.body(S.support_create_request()),
    responses: [created: @request]
  )

  def create(conn, _params) do
    with {:ok, request} <- SupportRequests.create(conn.assigns.user_context, conn.body_params) do
      conn |> put_status(:created) |> json(%{support_request: request})
    end
  end

  operation(:show,
    summary: "One support request: who received it, who replied, quiet hours, the no-reply card",
    parameters: [@id],
    responses: [ok: @request]
  )

  def show(conn, %{id: id}) do
    with {:ok, request} <- SupportRequests.show(conn.assigns.user_context, id),
         do: json(conn, %{support_request: request})
  end

  operation(:undo,
    summary: "Take a request back within 5 seconds (nobody is told)",
    parameters: [@id],
    responses: [ok: @request]
  )

  def undo(conn, %{id: id}) do
    with {:ok, request} <- SupportRequests.undo(conn.assigns.user_context, id),
         do: json(conn, %{support_request: request})
  end

  operation(:reply,
    summary: "Answer as a buddy: here, walk, call (with the sender's phone if shared) or text",
    parameters: [@id],
    request_body: S.body(S.reply_request()),
    responses: [created: {"Reply", "application/json", S.reply_response()}]
  )

  def reply(conn, %{id: id}) do
    with {:ok, reply} <-
           SupportRequests.reply(conn.assigns.user_context, id, conn.body_params) do
      conn |> put_status(:created) |> json(reply)
    end
  end
end
