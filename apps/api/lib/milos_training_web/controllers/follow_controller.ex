defmodule MilosTrainingWeb.FollowController do
  @moduledoc "Following people and boxes, and the requests a person answers (ADR-142, P2-M2)."

  use MilosTrainingWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias MilosTraining.Application.{Follows, SocialProfile}
  alias MilosTrainingWeb.Schemas.Social, as: S
  alias OpenApiSpex.{Parameter, Schema}

  action_fallback MilosTrainingWeb.FallbackController

  tags(["Follows"])
  security([%{"bearerAuth" => []}])

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

  @id %Parameter{name: :id, in: :path, required: true, schema: S.uuid()}
  @cursor %Parameter{name: :cursor, in: :query, required: false, schema: %Schema{type: :string}}
  @search %Parameter{
    name: :q,
    in: :query,
    required: false,
    description: "Keep only names containing this (case and accents ignored)",
    schema: %Schema{type: :string, maxLength: 80}
  }
  @target [
    %Parameter{
      name: :target_type,
      in: :path,
      required: true,
      schema: %Schema{type: :string, enum: ~w(user organization club)}
    },
    %Parameter{name: :target_id, in: :path, required: true, schema: S.uuid()}
  ]
  @no_content [no_content: {"Done", "application/json", %Schema{type: :object}}]

  operation(:create,
    summary: "Follow a person (a request they accept) or a published box (at once)",
    request_body: S.body(S.follow_request()),
    responses: [ok: {"Status", "application/json", S.follow_status_response()}]
  )

  def create(conn, _params) do
    %{target_type: type, target_id: id} = conn.body_params

    with {:ok, status} <- Follows.follow(conn.assigns.user_context, type, id),
         do: json(conn, status)
  end

  operation(:show,
    summary: "Whether you follow a person or box",
    parameters: @target,
    responses: [ok: {"Status", "application/json", S.follow_status_response()}]
  )

  def show(conn, %{target_type: type, target_id: id}) do
    with {:ok, status} <- Follows.status(conn.assigns.user_context, type, id),
         do: json(conn, status)
  end

  operation(:delete,
    summary: "Unfollow, or withdraw a request",
    parameters: @target,
    responses: [ok: {"Status", "application/json", S.follow_status_response()}]
  )

  def delete(conn, %{target_type: type, target_id: id}) do
    with {:ok, status} <- Follows.unfollow(conn.assigns.user_context, type, id),
         do: json(conn, status)
  end

  operation(:requests,
    summary: "People waiting for you to accept them",
    parameters: [@cursor],
    responses: [ok: {"Requests", "application/json", S.people_page()}]
  )

  def requests(conn, params) do
    with {:ok, page} <- Follows.requests(conn.assigns.user_context, params), do: json(conn, page)
  end

  operation(:accept,
    summary: "Accept a follow request",
    parameters: [@id],
    responses: @no_content
  )

  def accept(conn, %{id: id}) do
    with :ok <- Follows.accept(conn.assigns.user_context, id),
         do: send_resp(conn, :no_content, "")
  end

  operation(:remove,
    summary: "Decline a follow request, or remove a follower",
    parameters: [@id],
    responses: @no_content
  )

  def remove(conn, %{id: id}) do
    with :ok <- Follows.remove(conn.assigns.user_context, id),
         do: send_resp(conn, :no_content, "")
  end

  operation(:followers,
    summary: "People who follow you",
    parameters: [@cursor, @search],
    responses: [ok: {"Followers", "application/json", S.people_page()}]
  )

  def followers(conn, params) do
    with {:ok, page} <- Follows.followers(conn.assigns.user_context, params), do: json(conn, page)
  end

  operation(:following,
    summary: "People (type user) or boxes (type organization) you follow",
    parameters: [
      @cursor,
      @search,
      %Parameter{
        name: :type,
        in: :query,
        required: false,
        schema: %Schema{type: :string, enum: ~w(user organization)}
      }
    ],
    responses: [ok: {"Following", "application/json", S.people_page()}]
  )

  def following(conn, params) do
    with {:ok, page} <- Follows.following(conn.assigns.user_context, params), do: json(conn, page)
  end

  operation(:summary,
    summary: "Your counts for Εγώ: posts, followers, following, waiting requests",
    responses: [ok: {"Counts", "application/json", S.summary_response()}]
  )

  def summary(conn, _params) do
    with {:ok, summary} <- SocialProfile.me(conn.assigns.user_context), do: json(conn, summary)
  end

  operation(:booking_sharing,
    summary: "Show followers the classes you book, or stop (board 5 Q6)",
    request_body: S.body(S.booking_sharing_request()),
    responses: [ok: {"Setting", "application/json", S.booking_sharing()}]
  )

  def booking_sharing(conn, _params) do
    with {:ok, setting} <-
           SocialProfile.set_booking_sharing(conn.assigns.user_context, conn.body_params.enabled),
         do: json(conn, setting)
  end

  operation(:member_visibility,
    summary: "Keep yourself out of your clubs' «Μέλη» lists, or show again (board 7 Q1)",
    request_body: S.body(S.member_visibility()),
    responses: [ok: {"Setting", "application/json", S.member_visibility()}]
  )

  def member_visibility(conn, _params) do
    with {:ok, setting} <-
           SocialProfile.set_member_visibility(conn.assigns.user_context, conn.body_params.hidden),
         do: json(conn, setting)
  end

  operation(:around_visibility,
    summary: "Show your public posts in Γύρω μου at your neighbourhood, or stop (ADR-154)",
    request_body: S.body(MilosTrainingWeb.Schemas.Around.around_visibility_request()),
    responses: [
      ok: {"Setting", "application/json", MilosTrainingWeb.Schemas.Around.around_visibility()}
    ]
  )

  def around_visibility(conn, _params) do
    with {:ok, setting} <-
           SocialProfile.set_around_visibility(
             conn.assigns.user_context,
             conn.body_params.visible
           ),
         do: json(conn, setting)
  end
end
