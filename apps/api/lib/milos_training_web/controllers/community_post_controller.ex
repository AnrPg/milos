defmodule MilosTrainingWeb.CommunityPostController do
  @moduledoc "Posts, kudos and comments in a gym's club, and the member's feed (ADR-138, M7)."

  use MilosTrainingWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias MilosTraining.Application.{CommunityPosts, GetCommunityFeed}
  alias MilosTrainingWeb.Schemas.Community, as: S
  alias OpenApiSpex.{Parameter, Schema}

  action_fallback MilosTrainingWeb.FallbackController

  tags(["Community"])
  security([%{"bearerAuth" => []}])

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

  @id %Parameter{name: :id, in: :path, required: true, schema: S.uuid()}

  operation(:feed,
    summary: "Posts from your clubs, newest first",
    parameters: [
      %Parameter{name: :club_id, in: :query, required: false, schema: S.uuid()},
      %Parameter{name: :channel_id, in: :query, required: false, schema: S.uuid()},
      %Parameter{
        name: :mine,
        in: :query,
        required: false,
        description: "Only your own posts",
        schema: %Schema{type: :boolean}
      },
      %Parameter{name: :cursor, in: :query, required: false, schema: %Schema{type: :string}},
      %Parameter{
        name: :limit,
        in: :query,
        required: false,
        schema: %Schema{type: :integer, minimum: 1, maximum: 50}
      }
    ],
    responses: [ok: {"Feed page", "application/json", S.feed_response()}]
  )

  def feed(conn, params) do
    with {:ok, page} <- GetCommunityFeed.call(conn.assigns.user_context, params) do
      json(conn, page)
    end
  end

  operation(:create,
    summary: "Post in a channel of your gym's club, optionally attaching a journal entry",
    request_body: S.body(S.create_post_request()),
    responses: [created: {"Post", "application/json", S.post_response()}]
  )

  def create(conn, _params) do
    with {:ok, post} <- CommunityPosts.create(conn.assigns.tenant_context, conn.body_params) do
      conn |> put_status(:created) |> json(%{post: post})
    end
  end

  operation(:delete,
    summary: "Delete your post (staff: any post in their club)",
    parameters: [@id],
    responses: [no_content: {"Deleted", "application/json", %Schema{type: :object}}]
  )

  def delete(conn, %{id: id}) do
    with :ok <- CommunityPosts.delete(conn.assigns.tenant_context, id) do
      send_resp(conn, :no_content, "")
    end
  end

  operation(:hide,
    summary: "Staff: hide or show a post",
    parameters: [@id],
    request_body: S.body(S.flag_request(:hidden)),
    responses: [ok: {"Post", "application/json", S.post_response()}]
  )

  def hide(conn, %{id: id}) do
    with {:ok, post} <-
           CommunityPosts.hide(conn.assigns.tenant_context, id, conn.body_params.hidden) do
      json(conn, %{post: post})
    end
  end

  operation(:pin,
    summary: "Staff: pin or unpin an announcement",
    parameters: [@id],
    request_body: S.body(S.flag_request(:pinned)),
    responses: [ok: {"Post", "application/json", S.post_response()}]
  )

  def pin(conn, %{id: id}) do
    with {:ok, post} <-
           CommunityPosts.pin(conn.assigns.tenant_context, id, conn.body_params.pinned) do
      json(conn, %{post: post})
    end
  end

  operation(:kudos,
    summary: "Give or take back kudos",
    parameters: [@id],
    request_body: S.body(S.flag_request(:kudos)),
    responses: [ok: {"Post", "application/json", S.post_response()}]
  )

  def kudos(conn, %{id: id}) do
    with {:ok, post} <-
           CommunityPosts.kudos(conn.assigns.tenant_context, id, conn.body_params.kudos) do
      json(conn, %{post: post})
    end
  end

  operation(:comments,
    summary: "A post's comments, oldest first",
    parameters: [@id],
    responses: [ok: {"Comments", "application/json", S.comments_response()}]
  )

  def comments(conn, %{id: id}) do
    with {:ok, comments} <- CommunityPosts.comments(conn.assigns.tenant_context, id) do
      json(conn, %{comments: comments})
    end
  end

  operation(:comment,
    summary: "Comment on a post",
    parameters: [@id],
    request_body: S.body(S.comment_request()),
    responses: [created: {"Comment", "application/json", S.comment_response()}]
  )

  def comment(conn, %{id: id}) do
    with {:ok, comment} <-
           CommunityPosts.comment(conn.assigns.tenant_context, id, conn.body_params.body) do
      conn |> put_status(:created) |> json(%{comment: comment})
    end
  end

  operation(:delete_comment,
    summary: "Delete your comment (staff: any comment in their club)",
    parameters: [@id],
    responses: [no_content: {"Deleted", "application/json", %Schema{type: :object}}]
  )

  def delete_comment(conn, %{id: id}) do
    with :ok <- CommunityPosts.delete_comment(conn.assigns.tenant_context, id) do
      send_resp(conn, :no_content, "")
    end
  end

  operation(:hide_comment,
    summary: "Staff and group admins: hide or show a comment",
    parameters: [@id],
    request_body: S.body(S.flag_request(:hidden)),
    responses: [no_content: {"Done", "application/json", %Schema{type: :object}}]
  )

  def hide_comment(conn, %{id: id}) do
    with :ok <-
           CommunityPosts.hide_comment(conn.assigns.tenant_context, id, conn.body_params.hidden) do
      send_resp(conn, :no_content, "")
    end
  end
end
