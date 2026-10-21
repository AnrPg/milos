defmodule PaleeWeb.ProfilePostController do
  @moduledoc "Posts to your followers or to everyone, with kudos and comments (ADR-142, P2-M2)."

  use PaleeWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Palee.Application.ProfilePosts
  alias PaleeWeb.Schemas.Community, as: C
  alias PaleeWeb.Schemas.Social, as: S
  alias OpenApiSpex.{Parameter, Schema}

  action_fallback PaleeWeb.FallbackController

  tags(["Community"])
  security([%{"bearerAuth" => []}])

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

  @id %Parameter{name: :id, in: :path, required: true, schema: S.uuid()}
  @no_content [no_content: {"Deleted", "application/json", %Schema{type: :object}}]

  operation(:create,
    summary: "Post to your followers or to everyone, optionally attaching a journal entry",
    request_body: S.body(S.create_profile_post_request()),
    responses: [created: {"Post", "application/json", C.post_response()}]
  )

  def create(conn, _params) do
    with {:ok, post} <- ProfilePosts.create(conn.assigns.user_context, conn.body_params) do
      conn |> put_status(:created) |> json(%{post: post})
    end
  end

  operation(:delete, summary: "Delete your post", parameters: [@id], responses: @no_content)

  def delete(conn, %{id: id}) do
    with :ok <- ProfilePosts.delete(conn.assigns.user_context, id),
         do: send_resp(conn, :no_content, "")
  end

  operation(:kudos,
    summary: "Give or take back kudos",
    parameters: [@id],
    request_body: C.body(C.flag_request(:kudos)),
    responses: [ok: {"Post", "application/json", C.post_response()}]
  )

  def kudos(conn, %{id: id}) do
    with {:ok, post} <-
           ProfilePosts.kudos(conn.assigns.user_context, id, conn.body_params.kudos) do
      json(conn, %{post: post})
    end
  end

  operation(:comments,
    summary: "A post's comments, oldest first",
    parameters: [@id],
    responses: [ok: {"Comments", "application/json", C.comments_response()}]
  )

  def comments(conn, %{id: id}) do
    with {:ok, comments} <- ProfilePosts.comments(conn.assigns.user_context, id),
         do: json(conn, %{comments: comments})
  end

  operation(:comment,
    summary: "Comment on a post",
    parameters: [@id],
    request_body: C.body(C.comment_request()),
    responses: [created: {"Comment", "application/json", C.comment_response()}]
  )

  def comment(conn, %{id: id}) do
    with {:ok, comment} <-
           ProfilePosts.comment(conn.assigns.user_context, id, conn.body_params.body) do
      conn |> put_status(:created) |> json(%{comment: comment})
    end
  end

  operation(:delete_comment,
    summary: "Delete your comment, or any comment on your post",
    parameters: [@id],
    responses: @no_content
  )

  def delete_comment(conn, %{id: id}) do
    with :ok <- ProfilePosts.delete_comment(conn.assigns.user_context, id),
         do: send_resp(conn, :no_content, "")
  end
end
