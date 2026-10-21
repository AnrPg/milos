defmodule PaleeWeb.ClubPostController do
  @moduledoc """
  Posts, kudos and comments in any club you reach, from your personal session
  (ADR-143): the same actions as the gym routes, for open clubs run by a gym
  you may not belong to. Writes run in the scope of the gym that runs the club.
  """

  use PaleeWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Palee.Application.CommunityPosts
  alias PaleeWeb.Schemas.Community, as: S
  alias OpenApiSpex.{Parameter, Schema}

  action_fallback PaleeWeb.FallbackController

  tags(["Community"])
  security([%{"bearerAuth" => []}])

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

  @id %Parameter{name: :id, in: :path, required: true, schema: S.uuid()}
  @done {"Done", "application/json", %Schema{type: :object}}

  operation(:create,
    summary: "Post in a channel of a club you reach",
    request_body: S.body(S.create_post_request()),
    responses: [created: {"Post", "application/json", S.post_response()}]
  )

  def create(conn, _params) do
    with {:ok, post} <- CommunityPosts.create(context(conn), conn.body_params) do
      conn |> put_status(:created) |> json(%{post: post})
    end
  end

  operation(:delete,
    summary: "Delete your post (staff and group admins: any post they moderate)",
    parameters: [@id],
    responses: [no_content: @done]
  )

  def delete(conn, %{id: id}) do
    with :ok <- CommunityPosts.delete(context(conn), id), do: send_resp(conn, :no_content, "")
  end

  operation(:hide,
    summary: "Hide or show a post you moderate",
    parameters: [@id],
    request_body: S.body(S.flag_request(:hidden)),
    responses: [ok: {"Post", "application/json", S.post_response()}]
  )

  def hide(conn, %{id: id}) do
    with {:ok, post} <- CommunityPosts.hide(context(conn), id, conn.body_params.hidden),
         do: json(conn, %{post: post})
  end

  operation(:pin,
    summary: "Pin or unpin a post you moderate",
    parameters: [@id],
    request_body: S.body(S.flag_request(:pinned)),
    responses: [ok: {"Post", "application/json", S.post_response()}]
  )

  def pin(conn, %{id: id}) do
    with {:ok, post} <- CommunityPosts.pin(context(conn), id, conn.body_params.pinned),
         do: json(conn, %{post: post})
  end

  operation(:kudos,
    summary: "Give or take back kudos",
    parameters: [@id],
    request_body: S.body(S.flag_request(:kudos)),
    responses: [ok: {"Post", "application/json", S.post_response()}]
  )

  def kudos(conn, %{id: id}) do
    with {:ok, post} <- CommunityPosts.kudos(context(conn), id, conn.body_params.kudos),
         do: json(conn, %{post: post})
  end

  operation(:comments,
    summary: "A post's comments, oldest first",
    parameters: [@id],
    responses: [ok: {"Comments", "application/json", S.comments_response()}]
  )

  def comments(conn, %{id: id}) do
    with {:ok, comments} <- CommunityPosts.comments(context(conn), id),
         do: json(conn, %{comments: comments})
  end

  operation(:comment,
    summary: "Comment on a post",
    parameters: [@id],
    request_body: S.body(S.comment_request()),
    responses: [created: {"Comment", "application/json", S.comment_response()}]
  )

  def comment(conn, %{id: id}) do
    with {:ok, comment} <- CommunityPosts.comment(context(conn), id, conn.body_params.body) do
      conn |> put_status(:created) |> json(%{comment: comment})
    end
  end

  operation(:delete_comment,
    summary: "Delete your comment (or one you moderate)",
    parameters: [@id],
    responses: [no_content: @done]
  )

  def delete_comment(conn, %{id: id}) do
    with :ok <- CommunityPosts.delete_comment(context(conn), id),
         do: send_resp(conn, :no_content, "")
  end

  operation(:hide_comment,
    summary: "Hide or show a comment you moderate",
    parameters: [@id],
    request_body: S.body(S.flag_request(:hidden)),
    responses: [no_content: @done]
  )

  def hide_comment(conn, %{id: id}) do
    with :ok <- CommunityPosts.hide_comment(context(conn), id, conn.body_params.hidden),
         do: send_resp(conn, :no_content, "")
  end

  defp context(conn), do: conn.assigns.user_context
end
